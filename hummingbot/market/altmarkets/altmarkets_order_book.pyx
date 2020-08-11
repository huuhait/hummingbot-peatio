#!/usr/bin/env python
from decimal import Decimal

from aiokafka import ConsumerRecord
import bz2
import logging
import time
from sqlalchemy.engine import RowProxy
from typing import (
    Any,
    Optional,
    Dict
)
import ujson

from hummingbot.logger import HummingbotLogger
from hummingbot.core.event.events import TradeType
from hummingbot.core.data_type.order_book cimport OrderBook
from hummingbot.core.data_type.order_book_message import OrderBookMessage, OrderBookMessageType

_hob_logger = None


cdef class AltmarketsOrderBook(OrderBook):
    @classmethod
    def logger(cls) -> HummingbotLogger:
        global _hob_logger
        if _hob_logger is None:
            _hob_logger = logging.getLogger(__name__)
        return _hob_logger

    @classmethod
    def snapshot_message_from_exchange(cls,
                                       msg: Dict[str, Any],
                                       timestamp: Optional[float] = None,
                                       metadata: Optional[Dict] = None) -> OrderBookMessage:
        if metadata:
            msg.update(metadata)
        # print(f"Snap rawmsg: {msg}")
        msg_ts = int(time.time() * 1e-3)
        content = {
            "trading_pair": msg["trading_pair"],
            "update_id": msg_ts,
            "bids": msg["bids"],
            "asks": msg["asks"]
        }
        # print(f"Snap msg: {content}")
        return OrderBookMessage(OrderBookMessageType.SNAPSHOT, content, timestamp or msg_ts)

    @classmethod
    def trade_message_from_exchange(cls,
                                    msg: Dict[str, Any],
                                    timestamp: Optional[float] = None,
                                    metadata: Optional[Dict] = None) -> OrderBookMessage:
        if metadata:
            msg.update(metadata)
        msg_ts = int(msg["date"])
        content = {
            "trading_pair": msg["trading_pair"],
            "trade_type": float(TradeType.BUY.value) if msg["taker_type"] == "sell" else float(TradeType.SELL.value),
            "trade_id": msg["tid"],
            "update_id": msg_ts,
            "amount": msg["amount"],
            "price": msg["price"]
        }
        # print(f"Trade msg: {content}")
        return OrderBookMessage(OrderBookMessageType.DIFF, content, timestamp or msg_ts)

    @classmethod
    def diff_message_from_exchange(cls,
                                   msg: Dict[str, Any],
                                   timestamp: Optional[float] = None,
                                   metadata: Optional[Dict] = None) -> OrderBookMessage:
        if metadata:
            msg.update(metadata)
        # print(f"Diff raw_msg: {msg}")
        msg_ts = int(time.time() * 1e-3)
        content = {
            "trading_pair": msg["trading_pair"],
            "update_id": msg_ts,
            "bids": [msg["bids"]] if msg.get("bids", None) is not None else [['0.0', '0.0']],
            "asks": [msg["asks"]] if msg.get("asks", None) is not None else [['0.0', '0.0']]
        }
        for bid_ask in ["bids", "asks"]:
            for x in range(len(content[bid_ask])):
                if content[bid_ask][x][1] == '':
                    content[bid_ask][x][1] = '0.0'
        # print(f"Diff msg: {content}")
        return OrderBookMessage(OrderBookMessageType.DIFF, content, timestamp or msg_ts)

    @classmethod
    def snapshot_message_from_db(cls, record: RowProxy, metadata: Optional[Dict] = None) -> OrderBookMessage:
        msg = record["json"] if type(record["json"])==dict else ujson.loads(record["json"])
        if metadata:
            msg.update(metadata)
        msg_ts = int(time.time() * 1e-3)
        msg_key = list(msg.keys())[0]
        trading_pair = msg_key.split(".")[0]
        return OrderBookMessage(OrderBookMessageType.SNAPSHOT, {
            "trading_pair": trading_pair,
            "update_id": msg_ts,
            "bids": msg[msg_key]["bids"],
            "asks": msg[msg_key]["asks"]
        }, timestamp=msg_ts)

    @classmethod
    def diff_message_from_db(cls, record: RowProxy, metadata: Optional[Dict] = None) -> OrderBookMessage:
        print("Diff MSG from DB")
        ts = record["timestamp"]
        msg = record["json"] if type(record["json"])==dict else ujson.loads(record["json"])
        if metadata:
            msg.update(metadata)
        return OrderBookMessage(OrderBookMessageType.DIFF, {
            "trading_pair": msg["s"],
            "update_id": int(ts),
            "bids": msg["b"],
            "asks": msg["a"]
        }, timestamp=ts * 1e-3)

    @classmethod
    def snapshot_message_from_kafka(cls, record: ConsumerRecord, metadata: Optional[Dict] = None) -> OrderBookMessage:
        ts = record.timestamp
        msg = ujson.loads(record.value.decode())
        if metadata:
            msg.update(metadata)
        return OrderBookMessage(OrderBookMessageType.SNAPSHOT, {
            "trading_pair": msg["ch"].split(".")[1],
            "update_id": ts,
            "bids": msg["tick"]["bids"],
            "asks": msg["tick"]["asks"]
        }, timestamp=ts * 1e-3)

    @classmethod
    def diff_message_from_kafka(cls, record: ConsumerRecord, metadata: Optional[Dict] = None) -> OrderBookMessage:
        decompressed = bz2.decompress(record.value)
        msg = ujson.loads(decompressed)
        ts = record.timestamp
        if metadata:
            msg.update(metadata)
        return OrderBookMessage(OrderBookMessageType.DIFF, {
            "trading_pair": msg["s"],
            "update_id": ts,
            "bids": msg["bids"],
            "asks": msg["asks"]
        }, timestamp=ts * 1e-3)

    @classmethod
    def trade_message_from_db(cls, record: RowProxy, metadata: Optional[Dict] = None):
        msg = record
        msg_ts = int(msg["date"])
        # ts = record.timestamp
        # data = msg["tick"]["data"][0]
        if metadata:
            msg.update(metadata)
        return OrderBookMessage(OrderBookMessageType.TRADE, {
            "trading_pair": msg["trading_pair"],
            "trade_type": float(TradeType.BUY.value) if msg["taker_type"] == "sell" else float(TradeType.SELL.value),
            "trade_id": msg["tid"],
            "update_id": msg_ts,
            "amount": msg["amount"],
            "price": msg["price"]
        }, timestamp=msg_ts)

    @classmethod
    def from_snapshot(cls, msg: OrderBookMessage) -> "OrderBook":
        retval = AltmarketsOrderBook()
        retval.apply_snapshot(msg.bids, msg.asks, msg.update_id)
        return retval
