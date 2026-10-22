"""
Seed demo data for Pharmacy Store Application.

Run with: python -m backend.scripts.seed_demo

This creates the initial demo accounts and shop data needed for the project to function.

Default credentials (as specified in backend/.env.example):
- Super Admin: superadmin@medishop.local / SuperAdmin#2026
- Owner: +919876512345 / OwnerTemp#8821

Email delivery mode: "log only" by default.
Set SMTP_HOST and SMTP_FROM_EMAIL in .env to enable actual email sending.
"""

import asyncio
import json
import uuid

import asyncpg
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError

_hasher = PasswordHasher(time_cost=2, memory_cost=19456, parallelism=1, hash_len=32, salt_len=16)


def hash_password(plain: str) -> str:
    return _hasher.hash(plain)


async def seed_demo_data():
    """Seed the database with demo accounts and shop data."""
    pool = await asyncpg.create_pool(
        'postgresql://postgres:postgres@localhost:5432/medishop_dev',
        min_size=1, max_size=5
    )

    async with pool.acquire() as conn:
        print("=== Seeding Demo Data ===\n")

        # 1. Seed Super Admin
        print("1. Seeding Super Admin...")
        superadmin_email = 'superadmin@medishop.local'
        superadmin_password = 'SuperAdmin#2026'

        existing = await conn.fetchval(
            "SELECT id FROM users WHERE email_normalized = $1",
            superadmin_email
        )

        if not existing:
            sha_hash = hash_password(superadmin_password)
            await conn.execute(
                """INSERT INTO users
                   (full_name, role, password_hash, status, must_change_password,
                    email_normalized, created_at, updated_at)
                   VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW())""",
                'Super Admin', 'SUPER_ADMIN', sha_hash, 'ACTIVE', False,
                superadmin_email
            )
            print("   OK Super Admin created: superadmin@medishop.local")
        else:
            print("   OK Super Admin already exists, skipping.")

        # 2. Seed Owner
        print("\n2. Seeding Owner...")
        owner_phone = '+919876512345'
        owner_password = 'OwnerTemp#8821'

        existing = await conn.fetchval(
            "SELECT id FROM users WHERE phone_e164 = $1",
            owner_phone
        )

        if not existing:
            sha_hash = hash_password(owner_password)
            await conn.execute(
                """INSERT INTO users
                   (full_name, role, password_hash, status, must_change_password,
                    phone_e164, created_at, updated_at)
                   VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW())""",
                'Demo Owner', 'SHOP_OWNER', sha_hash, 'ACTIVE', False,
                owner_phone
            )
            print("   OK Owner created: +919876512345")
        else:
            print("   OK Owner already exists, skipping.")

        # 3. Seed Demo Shop
        print("\n3. Seeding Demo Shop...")
        shop_name = 'MediShop Demo Pharmacy'

        existing = await conn.fetchval(
            "SELECT id FROM shops WHERE phone_e164 = $1",
            owner_phone
        )

        if not existing:
            owner_id = await conn.fetchval(
                "SELECT id FROM users WHERE phone_e164 = $1",
                owner_phone
            )

            address = json.dumps({
                'city': 'Bengaluru',
                'line1': '12 MG Road',
                'line2': 'Near City Hospital',
                'state': 'Karnataka',
                'country': 'India',
                'postalCode': '560001'
            })

            shop_result = await conn.execute(
                """INSERT INTO shops
                   (shop_name, address, phone_e164, email_normalized,
                    licence_details, payment_settings, status, created_by)
                   VALUES ($1, $2, $3, $4, $5, $6, $7, $8)""",
                shop_name, address, owner_phone, None,
                None, '{}', 'ACTIVE', owner_id
            )

            await conn.execute(
                "UPDATE users SET owner_store_id = $1 WHERE id = $2",
                (await conn.fetchval("SELECT id FROM shops WHERE phone_e164 = $1")), owner_id
            )

            print("   OK Shop created: MediShop Demo Pharmacy")
            print("   OK Owner linked to shop")
        else:
            print("   OK Shop already exists, skipping.")

        # 4. Summary
        print("\n=== Seeding Complete ===\n")

        print("Default Login Credentials:")
        print("  Super Admin: superadmin@medishop.local / SuperAdmin#2026")
        print("  Owner:       +919876512345 / OwnerTemp#8821\n")

        print("Notes:")
        print("  - Owner must change password on first login")
        print("  - Emails are in 'log only' mode by default")
        print("  - Set SMTP_HOST/SMTP_FROM_EMAIL in .env to enable actual email sending")
        print("  - All email attempts stored in email_logs table")


if __name__ == "__main__":
    asyncio.run(seed_demo_data())