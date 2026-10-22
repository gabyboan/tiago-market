"""The linked CLI and psql must interpret the same staging result."""
import json
import unittest

from publish_grocery_batch import ingestion_result


class IngestionResultTest(unittest.TestCase):
    def setUp(self):
        self.report = {'publishable': 400, 'inserted_snapshots': 400, 'rejected_local': 0}

    def test_psql_run_id_before_multiline_json_report(self):
        output = 'a7f0d2ba-b1ec-4d51-b289-13d10984afc0\n' + json.dumps(self.report, indent=2) + '\n'
        self.assertEqual(ingestion_result(output), self.report)

    def test_linked_cli_and_plain_json(self):
        for value in (self.report, {'rows': [{'ingestion_report': json.dumps(self.report)}]}):
            self.assertEqual(ingestion_result(json.dumps(value)), self.report)

    def test_missing_or_unexpected_output_is_rejected(self):
        for output in ('{}', '[]', 'NOTICE: unexpected output\n' + json.dumps(self.report)):
            with self.subTest(output=output), self.assertRaises(ValueError):
                ingestion_result(output)


if __name__ == '__main__':
    unittest.main()
