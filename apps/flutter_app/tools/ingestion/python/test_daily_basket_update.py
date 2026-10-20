import unittest

from daily_basket_update import publication_decision


def products(status='ready', count=8):
    return [{'status': status, 'source': 'fixture', 'url': str(i)} for i in range(count)]


class DailyBasketDecisionTest(unittest.TestCase):
    def test_publishes_only_complete_two_source_batch(self):
        decision = publication_decision({'chedraui-mx': 0, 'merco-mx': 0}, products())
        self.assertTrue(decision['ready'])

    def test_source_failure_partial_batch_or_review_blocks_publication(self):
        cases = [
            ({'chedraui-mx': 1, 'merco-mx': 0}, products()),
            ({'chedraui-mx': 0, 'merco-mx': 0}, products(count=7)),
            ({'chedraui-mx': 0, 'merco-mx': 0}, products('pending_review')),
        ]
        for sources, report in cases:
            with self.subTest(sources=sources, count=len(report)):
                self.assertFalse(publication_decision(sources, report)['ready'])


if __name__ == '__main__':
    unittest.main()
