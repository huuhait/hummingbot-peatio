import hashlib
import hmac
from datetime import datetime, timezone, timedelta
from typing import Dict, Any
from hummingbot.connector.exchange.peatio.peatio_constants import Constants


class PeatioAuth():
    """
    Auth class required by AltMarkets.io API
    Learn more at https://peatio.io
    """
    def __init__(self, api_key: str, secret_key: str):
        self.api_key = api_key
        self.secret_key = secret_key
        # POSIX epoch for nonce
        self.date_epoch = datetime(1970, 1, 1, tzinfo=timezone.utc)

    def generate_signature(self, auth_payload) -> (Dict[str, Any]):
        """
        Generates a HS256 signature from the payload.
        :return: the HS256 signature
        """
        return hmac.new(
            self.secret_key.encode('utf-8'),
            msg=auth_payload.encode('utf-8'),
            digestmod=hashlib.sha256).hexdigest()

    def get_headers(self) -> (Dict[str, Any]):
        """
        Generates authentication headers required by AltMarkets.io
        :return: a dictionary of auth headers
        """
        # Must use UTC timestamps for nonce, can't use tracking nonce
        date_now = datetime.now(timezone.utc)
        posix_timestamp_millis = int(((date_now - self.date_epoch) // timedelta(microseconds=1)) // 1000)
        nonce = str(posix_timestamp_millis)
        auth_payload = nonce + self.api_key
        signature = self.generate_signature(auth_payload)
        return {
            "X-Auth-Apikey": self.api_key,
            "X-Auth-Nonce": nonce,
            "X-Auth-Signature": signature,
            "Content-Type": "application/json",
            "User-Agent": Constants.USER_AGENT
        }
