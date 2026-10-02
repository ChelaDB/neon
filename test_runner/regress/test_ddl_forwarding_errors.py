from __future__ import annotations

from typing import TYPE_CHECKING

import psycopg2
import pytest
from psycopg2.errors import ObjectNotInPrerequisiteState
from werkzeug.wrappers.response import Response

if TYPE_CHECKING:
    from fixtures.httpserver import ListenAddress
    from fixtures.neon_fixtures import VanillaPostgres
    from fixtures.port_distributor import PortDistributor
    from pytest_httpserver import HTTPServer

ENDPOINT = "/test/roles_and_databases"
UNAVAILABLE = "role and database changes are unavailable right now; try again"


def start_pg(vanilla_pg: VanillaPostgres, host: str, port: int):
    vanilla_pg.configure(
        [
            f"neon.console_url=http://{host}:{port}{ENDPOINT}",
            "shared_preload_libraries = 'neon'",
        ]
    )
    vanilla_pg.start()


def test_ddl_forwarding_errors_unreachable(
    vanilla_pg: VanillaPostgres, port_distributor: PortDistributor
):
    """An unreachable control plane gives a friendly message that hides the URL."""
    port = port_distributor.get_port()  # nothing listens here
    start_pg(vanilla_pg, "localhost", port)

    with vanilla_pg.cursor() as cur:
        with pytest.raises(ObjectNotInPrerequisiteState) as exc_info:
            cur.execute("CREATE ROLE r")
    err = exc_info.value
    assert err.pgcode == "55000"
    assert err.diag.message_primary == UNAVAILABLE
    assert "localhost" not in str(err)
    assert str(port) not in str(err)


@pytest.mark.parametrize(
    "status,body,expected",
    [
        (400, "custom refusal", "custom refusal"),
        (403, "", "role and database changes were refused (HTTP 403)"),
        # A whitespace-only body counts as empty
        (403, "  \n\t \r\n", "role and database changes were refused (HTTP 403)"),
        # Surrounding whitespace is trimmed from a message
        (400, "  \n padded refusal \r\n", "padded refusal"),
    ],
    ids=["body", "empty", "whitespace_only", "trimmed"],
)
def test_ddl_forwarding_errors_refused(
    httpserver: HTTPServer,
    vanilla_pg: VanillaPostgres,
    httpserver_listen_address: ListenAddress,
    status: int,
    body: str,
    expected: str,
):
    """A refusal by the control plane shows its body as is, or a generic text if empty."""
    (host, port) = httpserver_listen_address
    httpserver.expect_request(ENDPOINT, method="PATCH").respond_with_handler(
        lambda request: Response(status=status, response=body)
    )
    start_pg(vanilla_pg, host, port)

    with vanilla_pg.cursor() as cur:
        with pytest.raises(psycopg2.Error) as exc_info:
            cur.execute("CREATE ROLE r")
    assert exc_info.value.diag.message_primary == expected


@pytest.mark.parametrize(
    "body,expected",
    [
        # The 1023-byte limit falls inside a 2-byte character: it is dropped whole
        ("a" * 1022 + "\u00e9", "a" * 1022),
        # ... or inside a 3-byte character
        ("a" * 1021 + "\u20ac", "a" * 1021),
        # ... or inside a 4-byte character
        ("a" * 1020 + "\U0001f600", "a" * 1020),
        # A character that ends exactly at the limit is kept
        ("a" * 1021 + "\u00e9", "a" * 1021 + "\u00e9"),
    ],
    ids=["split_2_byte", "split_3_byte", "split_4_byte", "fits_exactly"],
)
def test_ddl_forwarding_errors_truncation(
    httpserver: HTTPServer,
    vanilla_pg: VanillaPostgres,
    httpserver_listen_address: ListenAddress,
    body: str,
    expected: str,
):
    """A long refusal is cut on a character boundary, never inside a character."""
    (host, port) = httpserver_listen_address
    httpserver.expect_request(ENDPOINT, method="PATCH").respond_with_handler(
        lambda request: Response(status=400, response=body.encode("utf-8"))
    )
    start_pg(vanilla_pg, host, port)

    with vanilla_pg.cursor() as cur:
        cur.execute("SHOW server_encoding")
        assert cur.fetchone() == ("UTF8",)
        with pytest.raises(psycopg2.Error) as exc_info:
            cur.execute("CREATE ROLE r")
    assert exc_info.value.diag.message_primary == expected
