CREATE SEQUENCE "public"."ticket_number_seq" INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1001 CACHE 1;--> statement-breakpoint
CREATE TABLE "idempotency_records" (
	"id" bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY (sequence name "idempotency_records_id_seq" INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1),
	"store_id" uuid NOT NULL,
	"scope_key" text NOT NULL,
	"idempotency_key" text NOT NULL,
	"user_id" uuid NOT NULL,
	"client_operation_id" uuid NOT NULL,
	"request_hash" text,
	"outcome" text NOT NULL,
	"result_body" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"resource_id" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"expires_at" timestamp with time zone,
	CONSTRAINT "idempotency_outcome_ck" CHECK (outcome in ('SYNCED', 'CONFLICT', 'FAILED_PERMANENT', 'CANCELLED'))
);
--> statement-breakpoint
CREATE TABLE "integration_health" (
	"key" text NOT NULL,
	"scope" text NOT NULL,
	"status" text NOT NULL,
	"message" text,
	"last_checked_at" timestamp with time zone NOT NULL,
	"last_ok_at" timestamp with time zone,
	"last_changed_at" timestamp with time zone,
	"consecutive_failures" integer DEFAULT 0 NOT NULL,
	CONSTRAINT "integration_health_key_scope_pk" PRIMARY KEY("key","scope")
);
--> statement-breakpoint
CREATE TABLE "languages" (
	"code" text PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"native_name" text NOT NULL,
	"enabled" boolean DEFAULT true NOT NULL,
	"is_default" boolean DEFAULT false NOT NULL,
	"catalog_version" text NOT NULL,
	"reviewed" boolean DEFAULT false NOT NULL,
	"coverage" double precision NOT NULL,
	"missing_keys" text[] DEFAULT '{}'::text[] NOT NULL,
	"rejected_keys" text[] DEFAULT '{}'::text[] NOT NULL,
	"published_at" timestamp with time zone NOT NULL
);
--> statement-breakpoint
CREATE TABLE "shop_profiles" (
	"store_id" uuid PRIMARY KEY NOT NULL,
	"name" text,
	"phone" text,
	"address" text,
	"email" text,
	"version" integer DEFAULT 0 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_by" uuid
);
--> statement-breakpoint
CREATE TABLE "stock_balances" (
	"store_id" uuid NOT NULL,
	"product_id" text NOT NULL,
	"quantity" integer DEFAULT 0 NOT NULL,
	"version" integer DEFAULT 0 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "stock_balances_store_id_product_id_pk" PRIMARY KEY("store_id","product_id"),
	CONSTRAINT "stock_balances_nonneg_ck" CHECK (quantity >= 0)
);
--> statement-breakpoint
CREATE TABLE "stock_movements" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"store_id" uuid NOT NULL,
	"movement_id" uuid NOT NULL,
	"product_id" text NOT NULL,
	"batch_no" text,
	"quantity_delta" integer NOT NULL,
	"reason" text NOT NULL,
	"reference_id" text,
	"note" text,
	"created_by" uuid NOT NULL,
	"device_id" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "stock_movements_nonzero_ck" CHECK (quantity_delta <> 0)
);
--> statement-breakpoint
CREATE TABLE "store_members" (
	"user_id" uuid NOT NULL,
	"store_id" uuid NOT NULL,
	"role" text NOT NULL,
	"status" text DEFAULT 'ACTIVE' NOT NULL,
	CONSTRAINT "store_members_user_id_store_id_pk" PRIMARY KEY("user_id","store_id")
);
--> statement-breakpoint
CREATE TABLE "stores" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"status" text DEFAULT 'ACTIVE' NOT NULL,
	"name" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "sync_changes" (
	"store_id" uuid NOT NULL,
	"seq" bigint NOT NULL,
	"entity" text NOT NULL,
	"entity_id" text NOT NULL,
	"version" integer NOT NULL,
	"deleted" boolean DEFAULT false NOT NULL,
	"data" jsonb,
	"source_operation_id" text,
	"changed_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "sync_changes_store_id_seq_pk" PRIMARY KEY("store_id","seq")
);
--> statement-breakpoint
CREATE TABLE "sync_counters" (
	"store_id" uuid PRIMARY KEY NOT NULL,
	"seq" bigint DEFAULT 0 NOT NULL
);
--> statement-breakpoint
CREATE TABLE "sync_logs" (
	"id" bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY (sequence name "sync_logs_id_seq" INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1),
	"store_id" uuid NOT NULL,
	"user_id" uuid NOT NULL,
	"device_id" text NOT NULL,
	"operation_id" text NOT NULL,
	"action" text NOT NULL,
	"result" text NOT NULL,
	"error_code" text,
	"duration_ms" integer,
	"request_id" text,
	"timestamp" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "sync_operations" (
	"id" bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY (sequence name "sync_operations_id_seq" INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1),
	"client_operation_id" uuid NOT NULL,
	"idempotency_key" text NOT NULL,
	"store_id" uuid NOT NULL,
	"user_id" uuid NOT NULL,
	"device_id" text NOT NULL,
	"module" text NOT NULL,
	"operation_type" text NOT NULL,
	"payload" jsonb,
	"payload_hash" text,
	"entity_id" text,
	"base_version" integer,
	"depends_on" uuid[] DEFAULT '{}'::uuid[] NOT NULL,
	"status" text NOT NULL,
	"server_resource_id" text,
	"attempt_count" integer DEFAULT 0 NOT NULL,
	"last_error_code" text,
	"last_error_message" text,
	"client_created_at" timestamp with time zone,
	"processed_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "sync_operations_status_ck" CHECK (status in ('RECEIVED', 'PROCESSING', 'SYNCED', 'CONFLICT', 'FAILED', 'RETRYABLE', 'CANCELLED'))
);
--> statement-breakpoint
CREATE TABLE "ticket_attachment_blobs" (
	"attachment_id" uuid PRIMARY KEY NOT NULL,
	"data" "bytea" NOT NULL
);
--> statement-breakpoint
CREATE TABLE "ticket_attachments" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"store_id" uuid NOT NULL,
	"uploaded_by_user_id" uuid NOT NULL,
	"file_name" text NOT NULL,
	"content_type" text NOT NULL,
	"size" integer NOT NULL,
	"ticket_id" uuid,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "ticket_events" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"ticket_id" uuid NOT NULL,
	"store_id" uuid NOT NULL,
	"type" text NOT NULL,
	"author_user_id" uuid NOT NULL,
	"author_role" text NOT NULL,
	"body" text,
	"from_status" text,
	"to_status" text,
	"attachment_ids" uuid[] DEFAULT '{}'::uuid[] NOT NULL,
	"client_request_id" uuid,
	"seq" bigint GENERATED ALWAYS AS IDENTITY (sequence name "ticket_events_seq_seq" INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1),
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "tickets" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"ticket_number" text NOT NULL,
	"store_id" uuid NOT NULL,
	"created_by_user_id" uuid NOT NULL,
	"client_request_id" uuid NOT NULL,
	"subject" text NOT NULL,
	"description" text NOT NULL,
	"category" text NOT NULL,
	"priority" text DEFAULT 'NORMAL' NOT NULL,
	"status" text DEFAULT 'OPEN' NOT NULL,
	"related_operation_id" uuid,
	"related_module" text,
	"assigned_to_user_id" uuid,
	"last_activity_at" timestamp with time zone DEFAULT now() NOT NULL,
	"last_activity_by" text NOT NULL,
	"resolved_at" timestamp with time zone,
	"closed_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "tickets_status_ck" CHECK (status in ('OPEN', 'IN_PROGRESS', 'WAITING_FOR_USER', 'RESOLVED', 'CLOSED')),
	CONSTRAINT "tickets_priority_ck" CHECK (priority in ('LOW', 'NORMAL', 'HIGH', 'CRITICAL')),
	CONSTRAINT "tickets_category_ck" CHECK (category in ('BUG', 'FEATURE_REQUEST', 'ACCOUNT', 'SYNC', 'DATA_CONFLICT', 'OTHER'))
);
--> statement-breakpoint
CREATE TABLE "tour_progress" (
	"user_id" uuid NOT NULL,
	"tour_version" text NOT NULL,
	"status" text NOT NULL,
	"last_step_id" text NOT NULL,
	"steps_seen" text[] DEFAULT '{}'::text[] NOT NULL,
	"completed_at" timestamp with time zone,
	"skipped_at" timestamp with time zone,
	"restarts" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "tour_progress_user_id_tour_version_pk" PRIMARY KEY("user_id","tour_version"),
	CONSTRAINT "tour_progress_status_ck" CHECK (status in ('IN_PROGRESS', 'COMPLETED', 'SKIPPED'))
);
--> statement-breakpoint
CREATE TABLE "translations" (
	"language_code" text NOT NULL,
	"key" text NOT NULL,
	"value" text NOT NULL,
	"catalog_version" text NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "translations_language_code_key_catalog_version_pk" PRIMARY KEY("language_code","key","catalog_version")
);
--> statement-breakpoint
CREATE TABLE "user_devices" (
	"user_id" uuid NOT NULL,
	"store_id" uuid NOT NULL,
	"device_id" text NOT NULL,
	"platform" text,
	"app_version" text,
	"last_active_at" timestamp with time zone DEFAULT now() NOT NULL,
	"last_sync_cursor" text,
	"last_successful_sync_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "user_devices_user_id_device_id_store_id_pk" PRIMARY KEY("user_id","device_id","store_id")
);
--> statement-breakpoint
CREATE TABLE "user_preferences" (
	"user_id" uuid PRIMARY KEY NOT NULL,
	"language" text,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "users" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"status" text DEFAULT 'ACTIVE' NOT NULL,
	"name" text,
	"roles" text[] DEFAULT '{}'::text[] NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "store_members" ADD CONSTRAINT "store_members_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "store_members" ADD CONSTRAINT "store_members_store_id_stores_id_fk" FOREIGN KEY ("store_id") REFERENCES "public"."stores"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "ticket_attachment_blobs" ADD CONSTRAINT "ticket_attachment_blobs_attachment_id_ticket_attachments_id_fk" FOREIGN KEY ("attachment_id") REFERENCES "public"."ticket_attachments"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "ticket_attachments" ADD CONSTRAINT "ticket_attachments_ticket_id_tickets_id_fk" FOREIGN KEY ("ticket_id") REFERENCES "public"."tickets"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "ticket_events" ADD CONSTRAINT "ticket_events_ticket_id_tickets_id_fk" FOREIGN KEY ("ticket_id") REFERENCES "public"."tickets"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "idempotency_scope_key_uq" ON "idempotency_records" USING btree ("store_id","scope_key","idempotency_key");--> statement-breakpoint
CREATE UNIQUE INDEX "stock_movements_store_movement_uq" ON "stock_movements" USING btree ("store_id","movement_id");--> statement-breakpoint
CREATE INDEX "sync_logs_store_ts_idx" ON "sync_logs" USING btree ("store_id","timestamp");--> statement-breakpoint
CREATE INDEX "sync_logs_store_op_idx" ON "sync_logs" USING btree ("store_id","operation_id");--> statement-breakpoint
CREATE UNIQUE INDEX "sync_operations_store_client_op_uq" ON "sync_operations" USING btree ("store_id","client_operation_id");--> statement-breakpoint
CREATE INDEX "sync_operations_store_status_created_idx" ON "sync_operations" USING btree ("store_id","status","created_at");--> statement-breakpoint
CREATE INDEX "sync_operations_store_device_status_idx" ON "sync_operations" USING btree ("store_id","device_id","status");--> statement-breakpoint
CREATE INDEX "ticket_attachments_ticket_idx" ON "ticket_attachments" USING btree ("ticket_id");--> statement-breakpoint
CREATE INDEX "ticket_events_ticket_idx" ON "ticket_events" USING btree ("ticket_id","seq");--> statement-breakpoint
CREATE UNIQUE INDEX "ticket_events_request_uq" ON "ticket_events" USING btree ("ticket_id","author_user_id","client_request_id");--> statement-breakpoint
CREATE UNIQUE INDEX "tickets_number_uq" ON "tickets" USING btree ("ticket_number");--> statement-breakpoint
CREATE UNIQUE INDEX "tickets_request_uq" ON "tickets" USING btree ("store_id","created_by_user_id","client_request_id");--> statement-breakpoint
CREATE INDEX "tickets_store_status_updated_idx" ON "tickets" USING btree ("store_id","status","updated_at");--> statement-breakpoint
CREATE INDEX "tickets_store_updated_idx" ON "tickets" USING btree ("store_id","updated_at","id");