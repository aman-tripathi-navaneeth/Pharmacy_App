ALTER TABLE "ticket_events" ADD COLUMN "visibility" text DEFAULT 'PUBLIC' NOT NULL;--> statement-breakpoint
ALTER TABLE "ticket_events" ADD COLUMN "meta" jsonb;--> statement-breakpoint
CREATE INDEX "tickets_status_activity_idx" ON "tickets" USING btree ("status","last_activity_at");--> statement-breakpoint
CREATE INDEX "tickets_assignee_status_idx" ON "tickets" USING btree ("assigned_to_user_id","status");--> statement-breakpoint
ALTER TABLE "ticket_events" ADD CONSTRAINT "ticket_events_visibility_ck" CHECK (visibility in ('PUBLIC', 'INTERNAL'));--> statement-breakpoint
ALTER TABLE "ticket_events" ADD CONSTRAINT "ticket_events_type_ck" CHECK (type in ('CREATED', 'MESSAGE', 'NOTE', 'STATUS_CHANGE', 'ASSIGNMENT', 'PRIORITY_CHANGE'));