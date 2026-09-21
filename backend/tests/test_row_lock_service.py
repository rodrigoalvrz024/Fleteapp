import unittest
from types import SimpleNamespace
from unittest.mock import MagicMock

from fastapi import HTTPException
from sqlalchemy.exc import OperationalError

from app.services.row_lock_service import lock_first


class RowLockTests(unittest.TestCase):
    def test_lock_is_bounded_within_current_transaction(self):
        query = MagicMock()
        row = object()
        query.with_for_update.return_value.first.return_value = row
        self.assertIs(lock_first(query), row)
        self.assertEqual(str(query.session.execute.call_args.args[0]), "SET LOCAL lock_timeout = '5s'")
        query.session.rollback.assert_not_called()

    def test_lock_timeout_rolls_back_and_returns_sanitized_conflict(self):
        query = MagicMock()
        query.with_for_update.return_value.first.side_effect = OperationalError(
            "private statement", {}, SimpleNamespace(pgcode="55P03"),
        )
        with self.assertRaises(HTTPException) as caught:
            lock_first(query)
        self.assertEqual(caught.exception.status_code, 409)
        self.assertNotIn("private", caught.exception.detail)
        query.session.rollback.assert_called_once_with()

    def test_unrelated_database_failure_is_not_misclassified(self):
        query = MagicMock()
        error = OperationalError("statement", {}, SimpleNamespace(pgcode="08006"))
        query.with_for_update.return_value.first.side_effect = error
        with self.assertRaises(OperationalError) as caught:
            lock_first(query)
        self.assertIs(caught.exception, error)
