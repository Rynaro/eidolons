package store

import bolt "go.etcd.io/bbolt"

// The fault-injection handle exists only in test builds.
func (s *Store) BackendForTest() *bolt.DB { return s.db }
