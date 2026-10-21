-- Reset the environment to its initial state (run before/after the presentation)
-- ON CLUSTER: drops on all 4 nodes
DROP DATABASE IF EXISTS demo SYNC;
DROP DATABASE IF EXISTS demo_rep ON CLUSTER cluster_study SYNC;
