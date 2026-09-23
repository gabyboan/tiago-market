import base64
import json
import unittest

from build_android_release import validate


class ReleaseConfigTest(unittest.TestCase):
    def setUp(self):
        self.values = {
            'SUPABASE_URL': 'https://example.supabase.co',
            'API_BASE_URL': 'https://example.supabase.co/functions/v1/api',
            'SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_example_client_key',
            'APP_ENV': 'pilot', 'CRASHLYTICS_ENABLED': True,
            'GOOGLE_WEB_CLIENT_ID': 'example.apps.googleusercontent.com',
        }

    def test_public_configuration(self):
        validate(self.values)

    def test_rejects_private_key_even_with_public_key_present(self):
        payload = base64.urlsafe_b64encode(json.dumps({'role': 'service_role'}).encode()).decode()
        for key in ('sb_secret_example', f'header.{payload}.signature'):
            with self.subTest(key_type=key.split('_')[0]):
                with self.assertRaises(ValueError):
                    validate(dict(self.values, SUPABASE_ANON_KEY=key))

    def test_rejects_extra_configuration(self):
        with self.assertRaises(ValueError):
            validate(dict(self.values, ANDROID_STORE_PASSWORD='private'))

    def test_rejects_missing_firebase_collection(self):
        with self.assertRaises(ValueError):
            validate(dict(self.values, CRASHLYTICS_ENABLED=False))

    def test_rejects_credentials_in_url(self):
        with self.assertRaises(ValueError):
            validate(dict(self.values, API_BASE_URL='https://user:password@example.com'))

    def test_rejects_insecure_url(self):
        with self.assertRaises(ValueError):
            validate(dict(self.values, SUPABASE_URL='http://example.supabase.co'))


if __name__ == '__main__':
    unittest.main()
