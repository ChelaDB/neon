"""
Event-trigger functions owned by a non-superuser are skipped whenever the
current user, and not only the session user, is a superuser.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from fixtures.neon_fixtures import Endpoint, NeonEnv

OWNER = "et_owner"
DBNAME = "et_app"

# Runs DDL only when the current user differs from the session user, so the
# test can tell whether the function ran in such a context.
ROLE_CHANGE_FUNCTION = """
CREATE FUNCTION public.et_owner_fn() RETURNS event_trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF current_user <> session_user THEN
        EXECUTE format('ALTER ROLE %I SUPERUSER', session_user);
    END IF;
END;
$$
"""


def setup_owner(endpoint: Endpoint):
    """A non-superuser owner in neon_superuser, as compute_ctl creates them."""
    with endpoint.cursor() as cur:
        cur.execute(
            """
            DO $$
            BEGIN
                IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'neon_superuser') THEN
                    CREATE ROLE neon_superuser NOLOGIN CREATEDB CREATEROLE;
                END IF;
            END
            $$
            """
        )
        cur.execute(
            f"CREATE ROLE {OWNER} LOGIN INHERIT CREATEROLE CREATEDB BYPASSRLS "
            "REPLICATION IN ROLE neon_superuser"
        )
        cur.execute(f"CREATE DATABASE {DBNAME} OWNER {OWNER}")


def owner_is_superuser(endpoint: Endpoint) -> bool:
    with endpoint.cursor() as cur:
        cur.execute("SELECT rolsuper FROM pg_roles WHERE rolname = %s", (OWNER,))
        row = cur.fetchone()
        assert row is not None
        return bool(row[0])


def test_owner_event_trigger_skipped_under_superuser_current_user(neon_simple_env: NeonEnv):
    """
    An owner's event-trigger function doesn't run while a trusted extension's
    script runs as a superuser (the current user), even though the session
    user is the owner.
    """
    env = neon_simple_env
    endpoint = env.endpoints.create_start("main")
    setup_owner(endpoint)

    with endpoint.cursor(dbname=DBNAME, user=OWNER) as cur:
        cur.execute(ROLE_CHANGE_FUNCTION)
        cur.execute(
            "CREATE EVENT TRIGGER et_owner_trg ON ddl_command_end "
            "EXECUTE FUNCTION public.et_owner_fn()"
        )
        # pg_trgm is trusted: its script runs as the bootstrap superuser
        cur.execute("CREATE EXTENSION pg_trgm")

    assert not owner_is_superuser(endpoint)


def test_owner_event_trigger_skipped_with_event_triggers_off(neon_simple_env: NeonEnv):
    """
    With neon.event_triggers off, a function owned by a role outside
    neon_superuser is still skipped while the current user is a superuser.
    """
    env = neon_simple_env
    endpoint = env.endpoints.create_start("main")
    setup_owner(endpoint)

    with endpoint.cursor(dbname=DBNAME, user=OWNER) as cur:
        cur.execute("CREATE ROLE et_helper NOLOGIN")
        cur.execute(f"GRANT et_helper TO {OWNER}")
        cur.execute("GRANT CREATE ON SCHEMA public TO et_helper")
        cur.execute(ROLE_CHANGE_FUNCTION)
        cur.execute("ALTER FUNCTION public.et_owner_fn() OWNER TO et_helper")
        cur.execute(
            "CREATE EVENT TRIGGER et_owner_trg ON ddl_command_end "
            "EXECUTE FUNCTION public.et_owner_fn()"
        )
        cur.execute("SET neon.event_triggers = false")
        cur.execute("CREATE EXTENSION pg_trgm")

    assert not owner_is_superuser(endpoint)


def test_owner_event_trigger_fires_for_owner_ddl(neon_simple_env: NeonEnv):
    """The owner's own event trigger still fires for the owner's own DDL."""
    env = neon_simple_env
    endpoint = env.endpoints.create_start("main")
    setup_owner(endpoint)

    with endpoint.cursor(dbname=DBNAME, user=OWNER) as cur:
        cur.execute("CREATE TABLE public.et_log (who name, tag text)")
        cur.execute(
            """
            CREATE FUNCTION public.et_log_fn() RETURNS event_trigger
            LANGUAGE plpgsql AS $$
            BEGIN
                INSERT INTO public.et_log VALUES (current_user, tg_tag);
            END;
            $$
            """
        )
        cur.execute(
            "CREATE EVENT TRIGGER et_log_trg ON ddl_command_end EXECUTE FUNCTION public.et_log_fn()"
        )
        cur.execute("CREATE TABLE public.t1 (x int)")
        cur.execute("SELECT who, tag FROM public.et_log")
        assert cur.fetchall() == [(OWNER, "CREATE TABLE")]
