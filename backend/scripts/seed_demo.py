import asyncio

import asyncpg

from app.common.identity import is_probably_email, normalize_email, normalize_phone
from app.common.security import hash_password
from app.core.config import get_settings


async def seed_demo_data() -> None:
    settings = get_settings()
    if not settings.DATABASE_URL.strip():
        raise RuntimeError("Set DATABASE_URL in backend/.env before seeding.")
    if (
        not settings.seed_superadmin_password.strip()
        or not settings.seed_owner_password.strip()
    ):
        raise RuntimeError(
            "Set SEED_SUPERADMIN_PASSWORD and SEED_OWNER_PASSWORD "
            "in backend/.env before seeding."
        )

    pool = await asyncpg.create_pool(settings.DATABASE_URL, min_size=1, max_size=2)
    try:
        async with pool.acquire() as conn:
            async with conn.transaction():
                admin_identifier = settings.seed_superadmin_identifier.strip()
                admin_email = (
                    normalize_email(admin_identifier)
                    if is_probably_email(admin_identifier)
                    else None
                )
                admin_phone = (
                    None
                    if admin_email
                    else normalize_phone(admin_identifier)
                )
                admin_id = await conn.fetchval(
                    """SELECT id FROM users
                       WHERE ($1::text IS NOT NULL AND email_normalized = $1)
                          OR ($2::text IS NOT NULL AND phone_e164 = $2)
                       LIMIT 1""",
                    admin_email,
                    admin_phone,
                )
                if admin_id is None:
                    admin_id = await conn.fetchval(
                        """INSERT INTO users
                           (full_name, role, password_hash, status,
                            email_normalized, phone_e164)
                           VALUES ('Super Admin', 'SUPER_ADMIN', $1, 'ACTIVE', $2, $3)
                           RETURNING id""",
                        hash_password(settings.seed_superadmin_password),
                        admin_email,
                        admin_phone,
                    )

                owner_identifier = settings.seed_owner_identifier.strip()
                owner_email = (
                    normalize_email(owner_identifier)
                    if is_probably_email(owner_identifier)
                    else None
                )
                owner_phone = (
                    None if owner_email else normalize_phone(owner_identifier)
                )
                owner_id = await conn.fetchval(
                    """SELECT id FROM users
                       WHERE ($1::text IS NOT NULL AND email_normalized = $1)
                          OR ($2::text IS NOT NULL AND phone_e164 = $2)
                       LIMIT 1""",
                    owner_email,
                    owner_phone,
                )
                if owner_id is None:
                    owner_id = await conn.fetchval(
                        """INSERT INTO users
                           (full_name, role, password_hash, status, must_change_password,
                            email_normalized, phone_e164)
                           VALUES ('Demo Owner', 'SHOP_OWNER', $1, 'INVITED', TRUE, $2, $3)
                           RETURNING id""",
                        hash_password(settings.seed_owner_password),
                        owner_email,
                        owner_phone,
                    )

                shop_id = await conn.fetchval(
                    "SELECT id FROM shops WHERE owner_user_id = $1 LIMIT 1",
                    owner_id,
                )
                if shop_id is None:
                    shop_id = await conn.fetchval(
                        """INSERT INTO shops
                           (shop_name, owner_user_id, address, phone_e164, status, created_by)
                           VALUES (
                             'MediShop Demo Pharmacy', $1,
                             '{"city":"Bengaluru","line1":"12 MG Road","state":"Karnataka","postalCode":"560001"}',
                             $2, 'ACTIVE', $3
                           )
                           RETURNING id""",
                        owner_id,
                        owner_phone,
                        admin_id,
                    )
                await conn.execute(
                    "UPDATE users SET owner_store_id = $1 WHERE id = $2",
                    shop_id,
                    owner_id,
                )
    finally:
        await pool.close()

    print("Demo administrator, owner, and shop are ready.")
    print("Credentials are configured in backend/.env.")


if __name__ == "__main__":
    asyncio.run(seed_demo_data())
