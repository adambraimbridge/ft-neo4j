#!/bin/bash -eu

setting() {
    setting="${1}"
    value="${2}"
    file="${3}"
    if [ -n "${value}" ]; then
        sed --in-place "s|.*${setting}=.*|${setting}=${value}|" conf/"${file}"
    fi
}

if [ "$1" == "neo4j" ]; then
    setting "keep_logical_logs" "${NEO4J_KEEP_LOGICAL_LOGS:-100M size}" neo4j.properties
    setting "dbms.pagecache.memory" "${NEO4J_CACHE_MEMORY:-512M}" neo4j.properties
    setting "wrapper.java.additional=-Dneo4j.ext.udc.source" "${NEO4J_UDC_SOURCE:-docker}" neo4j-wrapper.conf
    setting "wrapper.java.initmemory" "${NEO4J_HEAP_MEMORY:-512}" neo4j-wrapper.conf
    setting "wrapper.java.maxmemory" "${NEO4J_HEAP_MEMORY:-512}" neo4j-wrapper.conf
    setting "org.neo4j.server.thirdparty_jaxrs_classes" "${NEO4J_THIRDPARTY_JAXRS_CLASSES:-}" neo4j-server.properties
    setting "allow_store_upgrade" "${NEO4J_ALLOW_STORE_UPGRADE:-}" neo4j.properties

    if [ "${NEO4J_AUTH:-}" == "none" ]; then
        setting "dbms.security.auth_enabled" "false" neo4j-server.properties
    elif [[ "${NEO4J_AUTH:-}" == neo4j/* ]]; then
        password="${NEO4J_AUTH#neo4j/}"
        bin/neo4j start || \
            (cat data/log/console.log && echo "Neo4j failed to start" && exit 1)
        if ! curl --fail --silent --user "neo4j:${password}" http://localhost:7474/db/data/ >/dev/null ; then
            curl --fail --silent --show-error --user neo4j:neo4j \
                --data '{"password": "'"${password}"'"}' \
                --header 'Content-Type: application/json' \
                http://localhost:7474/user/neo4j/password
        fi
        bin/neo4j stop
    elif [ -n "${NEO4J_AUTH:-}" ]; then
        echo "Invalid value for NEO4J_AUTH: '${NEO4J_AUTH}'"
        exit 1
    fi

    setting "org.neo4j.server.webserver.address" "0.0.0.0" neo4j-server.properties
    setting "org.neo4j.server.database.mode" "${NEO4J_DATABASE_MODE:-}" neo4j-server.properties
    setting "ha.server_id" "${NEO4J_SERVER_ID:-}" neo4j.properties
    setting "ha.server" "${NEO4J_HA_ADDRESS:-}:6001" neo4j.properties
    setting "ha.cluster_server" "${NEO4J_HA_ADDRESS:-}:5001" neo4j.properties
    setting "ha.initial_hosts" "${NEO4J_INITIAL_HOSTS:-}" neo4j.properties
    echo "dbms.querylog.enabled=${DBMS_QUERYLOG_ENABLED:-true}">>conf/neo4j.properties
    echo "dbms.querylog.parameter_logging_enabled=${DBMS_QUERYLOG_PARAMETER_LOGGING_ENABLED:-true}">>conf/neo4j.properties
    echo "dbms.querylog.filename=${DBMS_QUERYLOG_FILENAME:-/dev/stdout}">>conf/neo4j.properties
    echo "dbms.querylog.threshold=${DBMS_QUERYLOG_THRESHOLD:-500ms}">>conf/neo4j.properties

    # Graphite integration start
    if [ "${GRAPHITE_ENABLED:-false}" = true ]; then
    	echo "metrics.enabled=${GRAPHITE_ENABLED}" >> conf/neo4j.properties
    	echo "metrics.graphite.enabled=${GRAPHITE_ENABLED:-true}" >> conf/neo4j.properties
    	echo "metrics.graphite.server=${GRAPHITE_ADDRESS}" >> conf/neo4j.properties
    	echo "metrics.graphite.interval=${GRAPHITE_INTERVAL:-3m}" >> conf/neo4j.properties
    	echo "metrics.prefix=${GRAPHITE_PREFIX}" >> conf/neo4j.properties
    fi
    # Graphite integration end

    # FT added settings start
    setting "org.neo4j.server.http.log.enabled" "${NEO4J_HTTP_LOG_ENABLED:-true}" neo4j-server.properties
    setting "org.neo4j.server.http.log.config" "/neo4j-http-logging.xml" neo4j-server.properties
    # FT added settings end

    [ -f "${EXTENSION_SCRIPT:-}" ] && . ${EXTENSION_SCRIPT}

    if [ -d /conf ]; then
        find /conf -type f -exec cp {} conf \;
    fi

    if [ -d /ssl ]; then
        num_certs=$(ls /ssl/*.cert 2>/dev/null | wc -l)
        num_keys=$(ls /ssl/*.key 2>/dev/null | wc -l)
        if [ $num_certs == "1" -a $num_keys == "1" ]; then
            cert=$(ls /ssl/*.cert)
            key=$(ls /ssl/*.key)
            setting "dbms.security.tls_certificate_file" $cert neo4j-server.properties
            setting "dbms.security.tls_key_file" $key neo4j-server.properties
        else
            echo "You must provide exactly one *.cert and exactly one *.key in /ssl."
            exit 1
        fi
    fi

    if [ -d /plugins ]; then
        find /plugins -type f -exec cp {} plugins \;
    fi

    exec bin/neo4j console
elif [ "$1" == "dump-config" ]; then
    if [ -d /conf ]; then
        cp --recursive conf/* /conf
    else
        echo "You must provide a /conf volume"
        exit 1
    fi
else
    exec "$@"
fi
