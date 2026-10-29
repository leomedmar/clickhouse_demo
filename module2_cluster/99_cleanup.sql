-- Reset module 2 (drops on all 4 nodes; also removes the Keeper paths)
DROP DATABASE IF EXISTS lab ON CLUSTER cluster_study SYNC;
