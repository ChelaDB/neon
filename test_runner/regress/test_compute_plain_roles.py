from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from fixtures.neon_fixtures import NeonEnv

PLAIN_ATTRS_QUERY = """
SELECT rolsuper, rolcreaterole, rolcreatedb, rolbypassrls, rolreplication
FROM pg_catalog.pg_roles WHERE rolname = %s
"""
MEMBERSHIP_QUERY = """
SELECT count(*) FROM pg_catalog.pg_auth_members m
JOIN pg_catalog.pg_roles r ON r.oid = m.member WHERE r.rolname = %s
"""


def test_compute_plain_roles(neon_simple_env: NeonEnv):
    """
    A role with `privileged: false` in the spec is created as a plain role:
    no special attributes and no membership in neon_superuser. A role without
    the flag keeps the default (member of neon_superuser).
    """
    env = neon_simple_env
    endpoint = env.endpoints.create_start("main")

    def apply_roles():
        endpoint.respec_deep(
            **{
                "spec": {
                    "skip_pg_catalog_updates": False,
                    "cluster": {
                        "roles": [
                            {
                                "name": "plain_r",
                                "encrypted_password": None,
                                "options": None,
                                "privileged": False,
                            },
                            {
                                "name": "default_r",
                                "encrypted_password": None,
                                "options": None,
                            },
                        ]
                    },
                }
            }
        )
        endpoint.reconfigure()

    def check_plain():
        with endpoint.cursor() as cur:
            cur.execute(PLAIN_ATTRS_QUERY, ("plain_r",))
            assert cur.fetchone() == (False, False, False, False, False)
            cur.execute(MEMBERSHIP_QUERY, ("plain_r",))
            assert cur.fetchone() == (0,)

    apply_roles()
    check_plain()

    # Dropping the role and reconfiguring brings it back, still plain.
    with endpoint.cursor() as cur:
        cur.execute("DROP ROLE plain_r")
    apply_roles()
    check_plain()

    # A role without the flag is still a member of neon_superuser.
    with endpoint.cursor() as cur:
        cur.execute(
            """
            SELECT count(*) FROM pg_catalog.pg_auth_members m
            JOIN pg_catalog.pg_roles r ON r.oid = m.member
            JOIN pg_catalog.pg_roles g ON g.oid = m.roleid
            WHERE r.rolname = 'default_r' AND g.rolname = 'neon_superuser'
            """
        )
        assert cur.fetchone() == (1,)
