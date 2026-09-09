import contextlib
import io
import json
import os
import unittest
from unittest.mock import patch
from urllib.error import URLError
import table_client

class ClientTest(unittest.TestCase):
    def test_missing_token(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(ValueError):
                table_client.call('heartbeat', {})

    def test_retries_preserve_request_id_and_body(self):
        requests = []
        def open_request(request, timeout):
            requests.append(request.data)
            if len(requests) == 1:
                raise URLError('temporary error')
            return io.BytesIO(json.dumps({'data': {'ok': True}}).encode())
        with patch.dict(os.environ, {'TABLE_HERMES_TOKEN': 'ht_' + 'a' * 64}), patch('table_client.urlopen', side_effect=open_request), patch('table_client.time.sleep'), contextlib.redirect_stderr(io.StringIO()) as captured:
            result = table_client.call('heartbeat', {})
            self.assertTrue(result['data']['ok'])
            self.assertEqual(requests[0], requests[1])
            self.assertNotIn('ht_', captured.getvalue())

    def test_arbitrary_action_rejected(self):
        with patch.dict(os.environ, {'TABLE_HERMES_TOKEN': 'ht_' + 'a' * 64}):
            with self.assertRaises(ValueError):
                table_client.call('execute_sql', {})

if __name__ == '__main__':
    unittest.main()
