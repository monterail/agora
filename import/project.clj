(defproject agora-import "1.0"
  :description "Script for data upload for the Github Data Challenge 2014"
  :license {:name "MIT"}
  :dependencies [[org.clojure/clojure "1.6.0"]
                 [cheshire "5.3.1"]
                 [org.clojure/java.jdbc "0.0.6"]
                 [postgresql/postgresql "8.4-702.jdbc4"]
                 [clj-time "0.8.0"]]
  :main agora-import.core/main)
