CREATE INDEX metahtml_url_accessed ON metahtml (url_hostpathquery_key(url) text_pattern_ops, accessed_at);
/*
SELECT count(*)
FROM metahtml m
WHERE
    --url_hostpathquery_key(url) like 'reuters.com/%' AND
    accessed_at = (SELECT max(accessed_at) FROM metahtml WHERE url_hostpathquery_key(url)=url_hostpathquery_key(m.url));
*/

/*
 * NOTE:
 * triggers are a complicated way of implementing the index above
 *
CREATE OR REPLACE FUNCTION metahtml_besturl_trigger_fnc()
RETURNS trigger AS
$$
BEGIN
    SELECT metahtml

    UPDATE metahtml SET besturl_hostpath=FALSE
    WHERE besturl_hostpath=TRUE AND uri_hostpath(url) = uri_hostpath(new.url);

    UPDATE metahtml SET besturl_hostpathquery=FALSE
    WHERE besturl_hostpathquery=TRUE AND uri_hostpathquery(url) = uri_hostpathquery(new.url);
RETURN NEW;
END;
$$
LANGUAGE 'plpgsql';


CREATE TRIGGER metahtml_besturl_trigger
BEFORE INSERT
ON metahtml
FOR EACH ROW
EXECUTE PROCEDURE metahtml_besturl_trigger_fnc();
*/





/*********************************************************************************
 * faster count(*) 
 */


/*
 * This function is taken from https://www.postgresql.org/docs/current/row-estimation-examples.html
 * It's good for very general queries, but bad for specific ones, especially text search.
 */
CREATE FUNCTION count_estimate(query text) RETURNS integer AS $$
DECLARE
  rec   record;
  rows  integer;
BEGIN
  FOR rec IN EXECUTE 'EXPLAIN ' || query LOOP
    rows := substring(rec."QUERY PLAN" FROM ' rows=([[:digit:]]+)');
    EXIT WHEN rows IS NOT NULL;
  END LOOP;
  RETURN rows;
END;
$$ LANGUAGE plpgsql VOLATILE STRICT;


/*
 * The following queries have very similar outputs
 */

/*
select count_estimate('select 1 from metahtml');
select count(*) from metahtml;
*/

/*
 * but the equivalent queries for text search are way off.
 */

/*
SELECT count_estimate($$
SELECT
    1
FROM metahtml
WHERE
    to_tsvector('simple', jsonb->'title'->'best'->'value') @@ to_tsquery('simple', 'covid');
    $$);
*/

/*
 * A rollup table can fix the problem.
 *
 * rollup fields: 
 *   url_host(url)
 *   jsonb->'timestamp.published'->best->'value'->>'lo'
 *   jsonb->'content'->'best'->>'value'


BEGIN;
    -- this table stores the raw rollup summaries
    CREATE TABLE metahtml_rollup_host_raw (
        hll         hll     NOT NULL,
        num         INTEGER NOT NULL,
        host    TEXT    ,
        PRIMARY KEY (host)
    );

    -- indexes ensure fast calculation of the max on each column
    CREATE INDEX metahtml_rollup_host_index_hll ON metahtml_rollup_host_raw (hll_cardinality(hll));
    CREATE INDEX metahtml_rollup_host_index_num ON metahtml_rollup_host_raw (num);

    -- the view simplifies presentation of the hll columns
    CREATE VIEW metahtml_rollup_host AS
    SELECT
        hll_cardinality(hll) AS num_unique_url,
        num,
        host
    FROM metahtml_rollup_host_raw;

    -- ensure that all rows already in the table get rolled up
    INSERT INTO metahtml_rollup_host_raw (hll, num, host)
    SELECT
        hll_add_agg(hll_hash_text(url)),
        count(1),
        url_host(url) AS host
    FROM metahtml
    GROUP BY host;

    -- an insert trigger ensures that all future rows get rolled up
    CREATE OR REPLACE FUNCTION metahtml_rollup_host_insert_f()
    RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
    BEGIN
        INSERT INTO metahtml_rollup_host_raw (hll, num, host) VALUES
            (hll_add(hll_empty(),hll_hash_text(new.url)), 1, url_host(new.url))
        ON CONFLICT (host)
        DO UPDATE SET
            hll = metahtml_rollup_host_raw.hll || excluded.hll,
            num = metahtml_rollup_host_raw.num +  excluded.num;
    RETURN NEW;
    END;
    $$;

    CREATE TRIGGER metahtml_rollup_host_insert_t
        AFTER INSERT 
        ON metahtml
        FOR EACH ROW
        EXECUTE PROCEDURE metahtml_rollup_host_insert_f();

    -- an update trigger ensures that updates do not affect the unique columns
    CREATE OR REPLACE FUNCTION metahtml_rollup_host_update_f()
    RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
    BEGIN
        IF new.url != url THEN
            RAISE EXCEPTION 'cannot update the "url" column due to unique rollup';
        END IF;
    RETURN NEW;
    END;
    $$;

    CREATE TRIGGER metahtml_rollup_host_update_t
        BEFORE UPDATE
        ON metahtml
        FOR EACH ROW
        EXECUTE PROCEDURE metahtml_rollup_host_update_f();

    -- a delete trigger ensures that deletes never occur
    CREATE OR REPLACE FUNCTION metahtml_rollup_host_delete_f()
    RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
    BEGIN
        RAISE EXCEPTION 'cannot delete from metahtml due to unique rollup';
    RETURN NEW;
    END;
    $$;

    CREATE TRIGGER metahtml_rollup_host_delete_t
        BEFORE DELETE
        ON metahtml
        FOR EACH ROW
        EXECUTE PROCEDURE metahtml_rollup_host_delete_f();
COMMIT;

BEGIN;
    DROP TABLE metahtml_rollup_host_raw CASCADE;
    DROP TRIGGER metahtml_rollup_host_insert_t ON metahtml;
    DROP TRIGGER metahtml_rollup_host_update_t ON metahtml;
    DROP TRIGGER metahtml_rollup_host_delete_t ON metahtml;
    DROP FUNCTION metahtml_rollup_host_insert_f;
    DROP FUNCTION metahtml_rollup_host_update_f;
    DROP FUNCTION metahtml_rollup_host_delete_f;
COMMIT;
*/

/* deleteme
CREATE TABLE urls_summary (
    host TEXT NOT NULL,
    distinct_path hll NOT NULL,
    distinct_path_query hll NOT NULL,
    num BIGINT NOT NULL,
    PRIMARY KEY (host)
);

INSERT INTO rollups (name, event_table_name, event_id_sequence_name, sql)
VALUES ('urls_summary', 'urls', 'urls_id_urls_seq', $$
    INSERT INTO urls_summary
        (host,distinct_path,distinct_path_query,num)
    SELECT
        host,
        hll_add_agg(hll_hash_text(path)),
        hll_add_agg(hll_hash_text(path || query)),
        count(1)
    FROM urls
    WHERE
        id_urls>=$1 AND
        id_urls<$2
    GROUP BY host
    ON CONFLICT (host)
    DO UPDATE SET
        distinct_path = urls_summary.distinct_path || excluded.distinct_path,
        distinct_path_query = urls_summary.distinct_path_query || excluded.distinct_path_query,
        num = urls_summary.num+excluded.num
    ;
$$);
*/
