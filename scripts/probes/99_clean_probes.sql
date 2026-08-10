-- Drop all probe artifacts.
DROP SCHEMA IF EXISTS dev.probes CASCADE;
DROP TABLE IF EXISTS dev.analytics.hello_py_probe;
DROP TABLE IF EXISTS dev.analytics.io_probe;
