-- Family sessions must distinguish the authenticated account owner from the
-- learner receiving tutoring. Parent accounts continue to own payment,
-- consent, and access; child_id carries the learner identity.

BEGIN;

-- Children are now durable learner records. They must not be deleted and
-- recreated when a parent edits their family profile because sessions and
-- learning goals need a stable foreign key.
ALTER TABLE public.children
  ADD COLUMN IF NOT EXISTS subjects text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS preferred_language text,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS archived_at timestamptz;

COMMENT ON TABLE public.children IS
  'Stable learner profiles managed by a parent account. Archive rather than delete once referenced.';

COMMENT ON COLUMN public.children.archived_at IS
  'When set, the learner is hidden from new bookings but retained for session and progress history.';

-- Preserve the richer signup data that previously lived only in
-- profiles.children_info. Name + grade is the only legacy join key available,
-- so use the first matching JSON entry and leave unmatched rows unchanged.
WITH legacy_child_data AS (
  SELECT DISTINCT ON (
    profile.id,
    item.value ->> 'name',
    item.value ->> 'grade'
  )
    profile.id AS parent_id,
    item.value
  FROM public.profiles AS profile
  CROSS JOIN LATERAL jsonb_array_elements(
    CASE
      WHEN jsonb_typeof(profile.children_info) = 'array' THEN profile.children_info
      ELSE '[]'::jsonb
    END
  ) WITH ORDINALITY AS item(value, position)
  ORDER BY
    profile.id,
    item.value ->> 'name',
    item.value ->> 'grade',
    item.position
)
UPDATE public.children AS child
SET
  subjects = ARRAY(
    SELECT jsonb_array_elements_text(
      CASE
        WHEN jsonb_typeof(item.value -> 'subjects') = 'array'
          THEN item.value -> 'subjects'
        ELSE '[]'::jsonb
      END
    )
  ),
  preferred_language = COALESCE(
    NULLIF(item.value ->> 'preferredLanguage', ''),
    child.preferred_language
  ),
  updated_at = now()
FROM legacy_child_data AS item
WHERE item.parent_id = child.parent_id
  AND item.value ->> 'name' = child.name
  AND item.value ->> 'grade' = child.grade_level;

-- Keep legacy signup compatible, but never replace established learner rows.
-- All post-signup edits now use the children table directly.
CREATE OR REPLACE FUNCTION public.sync_children_from_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  child_item jsonb;
BEGIN
  IF NEW.role = 'parent'
     AND NEW.children_info IS NOT NULL
  THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.children WHERE parent_id = NEW.id
    ) AND jsonb_typeof(NEW.children_info) = 'array' THEN
      FOR child_item IN SELECT * FROM jsonb_array_elements(NEW.children_info)
      LOOP
        IF jsonb_typeof(child_item) = 'object'
           AND NULLIF(btrim(child_item ->> 'name'), '') IS NOT NULL
           AND NULLIF(btrim(child_item ->> 'grade'), '') IS NOT NULL
        THEN
          INSERT INTO public.children (
            parent_id,
            name,
            grade_level,
            subjects,
            preferred_language
          )
          VALUES (
            NEW.id,
            btrim(child_item ->> 'name'),
            btrim(child_item ->> 'grade'),
            ARRAY(
              SELECT jsonb_array_elements_text(
                CASE
                  WHEN jsonb_typeof(child_item -> 'subjects') = 'array'
                    THEN child_item -> 'subjects'
                  ELSE '[]'::jsonb
                END
              )
            ),
            NULLIF(child_item ->> 'preferredLanguage', '')
          );
        END IF;
      END LOOP;
    END IF;

    -- Do not retain a second, stale copy of learner personal information.
    UPDATE public.profiles
    SET children_info = NULL
    WHERE id = NEW.id
      AND children_info IS NOT NULL;
  END IF;
  RETURN NEW;
END;
$$;

-- Existing parents now use the normalized learner rows exclusively.
UPDATE public.profiles AS profile
SET children_info = NULL
WHERE profile.role = 'parent'
  AND profile.children_info IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM public.children WHERE parent_id = profile.id
  );

ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS child_id uuid
    REFERENCES public.children(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_sessions_child_scheduled_at
  ON public.sessions (child_id, scheduled_at DESC)
  WHERE child_id IS NOT NULL;

COMMENT ON COLUMN public.sessions.student_id IS
  'Authenticated family/student account that owns booking, payment, consent, and access. For a parent booking, the learner is sessions.child_id.';

COMMENT ON COLUMN public.sessions.child_id IS
  'Child receiving tutoring. Required for new parent bookings; null for independent student accounts and unresolved legacy sessions.';

-- Historical sessions can be assigned safely only when a parent has exactly
-- one learner. Never guess for multi-child families.
WITH only_children AS (
  SELECT parent_id, (array_agg(id ORDER BY id))[1] AS child_id
  FROM public.children
  WHERE archived_at IS NULL
  GROUP BY parent_id
  HAVING count(*) = 1
)
UPDATE public.sessions AS session
SET child_id = only_children.child_id
FROM only_children
WHERE session.student_id = only_children.parent_id
  AND session.child_id IS NULL;

-- Enforce learner ownership on new bookings and explicit reassignment without
-- breaking updates to unresolved historical sessions.
CREATE OR REPLACE FUNCTION public.validate_session_learner()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  account_role text;
BEGIN
  SELECT role INTO account_role
  FROM public.profiles
  WHERE id = NEW.student_id;

  IF account_role = 'parent' THEN
    IF NEW.child_id IS NULL THEN
      RAISE EXCEPTION 'Parent bookings require a child'
        USING ERRCODE = '23514';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM public.children
      WHERE id = NEW.child_id
        AND parent_id = NEW.student_id
        AND archived_at IS NULL
    ) THEN
      RAISE EXCEPTION 'Selected child does not belong to the booking parent or is archived'
        USING ERRCODE = '23514';
    END IF;
  ELSIF NEW.child_id IS NOT NULL THEN
    RAISE EXCEPTION 'Independent student bookings cannot select a parent-managed child'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sessions_validate_learner ON public.sessions;
CREATE TRIGGER sessions_validate_learner
  BEFORE INSERT OR UPDATE OF student_id, child_id
  ON public.sessions
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_session_learner();

COMMIT;
