from __future__ import annotations

from typing import TYPE_CHECKING

import psycopg2
import pytest
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
        with pytest.raises(psycopg2.OperationalError) as exc_info:
            cur.execute("CREATE ROLE r")
    err = exc_info.value
    assert err.pgcode == "08006"
    assert err.diag.message_primary == UNAVAILABLE
    assert "localhost" not in str(err)
    assert str(port) not in str(err)


@pytest.mark.parametrize(
    "status,body,expected",
    [
        (400, "custom refusal", "custom refusal"),
        (403, "", "role and database changes were refused (HTTP 403)"),
    ],
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
