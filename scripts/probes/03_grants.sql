-- Probe 5: is the built-in `account users` group grantable on FE?
GRANT SELECT ON TABLE dev.probes.toy TO `account users`;
SHOW GRANTS ON TABLE dev.probes.toy
