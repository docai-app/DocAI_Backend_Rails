class CreateOperationsReporting < ActiveRecord::Migration[7.0]
  def up
    create_table :essay_operation_events, id: :uuid do |t|
      t.references :essay_grading, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :event, null: false
      t.string :kind
      t.integer :attempts
      t.column :occurred_at, :timestamptz, null: false
    end
    add_index :essay_operation_events, [:event, :occurred_at], name: 'idx_essay_operation_events_period'
    create_table :operations_report_deliveries, id: :uuid do |t|
      t.datetime :period_start, null: false
      t.datetime :period_end, null: false
      t.string :state, null: false, default: 'preparing'
      t.datetime :claimed_at
      t.datetime :sent_at
      t.string :failure_class
      t.jsonb :summary, null: false, default: {}
      t.timestamps
    end
    add_index :operations_report_deliveries, :period_end, unique: true
    install_triggers
  end

  def install_triggers
    # Database triggers observe update_columns/update_all too. They do not enqueue
    # or change business status. No historical submission/completion is invented.
    execute <<~SQL
      CREATE OR REPLACE FUNCTION public.capture_essay_operation() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_TABLE_NAME = 'essay_gradings' THEN
          IF NEW.meta->'last_grading_error' IS NOT NULL AND
            (TG_OP = 'INSERT' OR NEW.meta->'last_grading_error' IS DISTINCT FROM OLD.meta->'last_grading_error') THEN
            INSERT INTO public.essay_operation_events(id, essay_grading_id, event, kind, occurred_at)
            VALUES(gen_random_uuid(), NEW.id, 'error', LEFT(NEW.meta->'last_grading_error'->>'stage', 64), clock_timestamp());
          END IF;
          IF TG_OP = 'INSERT' THEN
            IF NEW.status <> 3 THEN
              INSERT INTO public.essay_operation_events(id, essay_grading_id, event, occurred_at)
              VALUES(gen_random_uuid(), NEW.id, 'submitted', clock_timestamp());
            END IF;
          ELSIF OLD.status = 3 AND NEW.status <> 3 THEN
            INSERT INTO public.essay_operation_events(id, essay_grading_id, event, occurred_at)
            VALUES(gen_random_uuid(), NEW.id, 'submitted', clock_timestamp());
          END IF;
          IF TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status THEN
            INSERT INTO public.essay_operation_events(id, essay_grading_id, event, occurred_at)
            VALUES(gen_random_uuid(), NEW.id,
              CASE NEW.status WHEN 0 THEN 'pending' WHEN 1 THEN 'graded' WHEN 2 THEN 'stopped' ELSE 'draft' END,
              clock_timestamp());
          END IF;
        ELSE
          IF TG_OP = 'INSERT' OR NEW.state IS DISTINCT FROM OLD.state OR NEW.token IS DISTINCT FROM OLD.token THEN
            INSERT INTO public.essay_operation_events(id, essay_grading_id, event, kind, attempts, occurred_at)
            VALUES(gen_random_uuid(), NEW.essay_grading_id, 'generation_' || NEW.state, NEW.kind, NEW.attempts, clock_timestamp());
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$;
      DROP TRIGGER IF EXISTS essay_operations_status ON public.essay_gradings;
      DROP TRIGGER IF EXISTS essay_operations_generation ON public.essay_generation_runs;
      CREATE TRIGGER essay_operations_status AFTER INSERT OR UPDATE OF status, meta ON public.essay_gradings
        FOR EACH ROW EXECUTE FUNCTION public.capture_essay_operation();
      CREATE TRIGGER essay_operations_generation AFTER INSERT OR UPDATE OF state, token ON public.essay_generation_runs
        FOR EACH ROW EXECUTE FUNCTION public.capture_essay_operation();
    SQL
  end

  def down
    execute 'DROP TRIGGER IF EXISTS essay_operations_status ON public.essay_gradings'
    execute 'DROP TRIGGER IF EXISTS essay_operations_generation ON public.essay_generation_runs'
    execute 'DROP FUNCTION IF EXISTS public.capture_essay_operation()'
    drop_table :operations_report_deliveries
    drop_table :essay_operation_events
  end
end
