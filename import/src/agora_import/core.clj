(ns agora-import.core
  (:require [clojure.java.io :as io]
            [cheshire.core :refer :all]
            [clojure.pprint :refer [pprint]]
            [clojure.java.jdbc :as jdbc]
            [clj-time.core :as timecore]
            [clj-time.local :as lt]
            [clj-time.format :as timef]
            [clj-time.coerce :as timec]))


(def db
  "Basic database connection settings"
  {:classname   "org.postgresql.Driver"
   :subprotocol "postgresql"
   :subname     "//localhost:5432/DBNAME"
   :user        "DBUSER"
   :password    "DBPASS"
   })


(defn create-events-table
  "Create events table for the GitHub Data Challenge"
  [table-name]
  (clojure.java.jdbc/create-table
   table-name
   [:date   "date"]
   [:actor  "varchar(255)"]
   [:repo   "varchar(255)"]
   [:type   "varchar(50)"]))


(defn get-files-list
  "Retuns a list of json files within path"
  ([path] (get-files-list path "json"))
  ([path file-type]
     (let [file-ext (re-pattern (str ".*" file-type "$"))]
       (->> path
            (clojure.java.io/file)
            (.listFiles)
            (filter #(re-matches file-ext (.getName %)))))))


(defn parse-json-stream 
  "Returns a stream of parsed JSON objects"
  [filename]
  (let [rdr (io/reader filename)]
    (parsed-seq rdr true)))


(defn slim-data 
  "Keep only data needed for this analysis"
  [json-object]
  (let [utc-date (timef/parse (timef/formatter "yyyy-MM-dd'T'HH:mm:ssZ") (:created_at json-object))
        sql-date (timec/to-sql-date (timecore/date-time (timecore/year  utc-date)
                                                        (timecore/month utc-date)
                                                        (timecore/day   utc-date)))]
        {:repo  (get-in json-object [:repository :url])
         :type  (:type json-object)
         :date  sql-date
         :actor (:actor json-object)}))
    

(defn upload-collection
  "Upload data into postgres"
  [table-name json-files-path]
  (doseq [file (get-files-list json-files-path)]
    (jdbc/transaction
     (doseq [json-object (parse-json-stream file)]
       (jdbc/insert-records table-name (slim-data json-object))))))


(defn main
  "Create table and upload selected data"
  [json-files-path]
  (let [table-name :rawevents]
    (jdbc/with-connection db
      (create-events-table table-name)
      (upload-collection table-name json-files-path))))
