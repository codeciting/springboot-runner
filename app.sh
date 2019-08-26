#!/usr/bin/env bash

TOOL_NAME="SpringBoot Runner"

if [[ ${TERM} =~ ^xterm ]]
then
    function logInfo() {
        echo -en "\033[32m["${TOOL_NAME}"]\033[0m "
        echo -e $*
    }
    function logError() {
        echo -en "\033[31m["${TOOL_NAME}"]\033[0m Error: "
        echo -e $*
    }
else
    function logInfo() {
        echo -n "[${TOOL_NAME}][INFO ] "
        echo $*
    }
    function logError() {
        echo -n "[${TOOL_NAME}][ERROR] Error: "
        echo $*
    }
fi

# Usage: ./bin/app.sh stop|start|status|restart
BIN_DIR=`dirname $0`

# All spring boot options.
# See ./spring-boot.config.sh
OPTIONS_NAMES="APP_PORT CONF_FOLDER PID_FILE APP_NAME RUN_ARGS JAVA_HOME JAVA_OPTS JARFILE DEBUG RUNNER_TIMEOUT"

logInfo "SpringBoot Template v0.0.1"
logInfo "- - - - -"
logInfo "This script helps you run a jar app."
logInfo "Datetime: `date "+%Y-%m-%d %H:%M:%S"`"
logInfo "Working Directory: `pwd`"
logInfo "---------"

function start {
    BOOTSTRAP="${JAVA_HOME}/bin/java ${JAVA_OPTS} `parseRunArgs ${RUN_ARGS} server.port=${APP_PORT} spring.profiles.active=${ACTIVATE_PROFILES}` -jar ${JARFILE}"

    TMP_ERROR_LOG_FILE=${APP_NAME}.error.`date "+%Y%m%d%H%M%S"`.log

    if pkill -0 -f $APP_NAME.jar > /dev/null 2>&1
    then
        logError "Service [$APP_NAME] is already running. Ignoring startup request."
        exit 1
    fi

    # Start the server and output bootstrap log to tmp dir.
    nohup ${BOOTSTRAP} >> /tmp/${TMP_ERROR_LOG_FILE} < /dev/null 2>&1   &

    pid=$!

    echo ${pid} > ${PID_FILE}

    logInfo "${BOOTSTRAP}"
    logInfo -n "Starting ${APP_NAME}"
    echo -n " "
    timeout_counter=${RUNNER_TIMEOUT}
    while [[ `ping` -ne '0' ]]
    do
        sleep 1
        echo -n .
        if ! isAlive
        then
            echo ""
            logError "Failed to start application. See `pwd`/${APP_NAME}.error.log for more details."
            mv /tmp/${TMP_ERROR_LOG_FILE} ${TMP_ERROR_LOG_FILE}
            exit 1
        fi
        ((timeout_counter=timeout_counter-1))
        if [[ ${timeout_counter} -eq 0 ]]
        then
            echo ""
            logError "Timeout to start application. See `pwd`/${APP_NAME}.error.log for more details."
            mv /tmp/${TMP_ERROR_LOG_FILE} ${TMP_ERROR_LOG_FILE}

            pkill -f ${JARFILE} > /dev/null 2>&1

            while isAlive
            do
                sleep 1
            done

            exit 1
        fi
    done

    echo ""
    logInfo "${APP_NAME} ready at `date "+%Y-%m-%d %H:%M:%S"`"
    popd
    exit 0
}

function stop {
    if ! isAlive
    then
        if [[ $1 == 'ignore' ]]
        then
            logInfo "Service [$APP_NAME] is not running."
        else
            logError "Service [$APP_NAME] is not running. Ignoring shutdown request."
            rm -f ${PID_FILE}
            exit 1
        fi
    fi

    ## First, we will try to trigger a controlled shutdown using
    ## spring-boot-actuator
    #curl -X POST http://localhost:$APP_PORT/shutdown < /dev/null > /dev/null 2>&1

    pkill -f ${JARFILE} > /dev/null 2>&1

    logInfo -n "Stopping ${APP_NAME} "
    echo -n " "

    while isAlive
    do
        sleep 1
        echo -n .
    done

    echo ""
    logInfo "Service ${APP_NAME} is stopped at `date "+%Y-%m-%d %H:%M:%S"`."

    rm -f ${PID_FILE}

    # Wait until the server process has shut down
    #    attempts=0
    #    while pkill -0 -f $JARFILE > /dev/null 2>&1
    #    do
    #        attempts=$[$attempts + 1]
    #        if [ $attempts -gt ${STOP_WAIT_TIME} ]
    #        then
    #            # We have waited too long. Kill it.
    #            pkill -f $JARFILE > /dev/null 2>&1
    #        fi
    #        sleep 1s
    #    done
}

function status() {
    if pkill -0 -f $JARFILE > /dev/null 2>&1
    then
        logInfo "Service [$APP_NAME] is running, pid = `cat ${PID_FILE}`."
    else
        logInfo "Service [$APP_NAME] is not running,."
    fi
}


function parseRunArgs() {
    args=
    for PAIR in $* ; do
        args="${args} -D${PAIR}"
    done
    echo ${args}
}

function ping () {
    curl -I http://localhost:${APP_PORT}/ > /dev/null 2>/dev/null
    echo $?
}

function isAlive () {
    pkill -0 -f $JARFILE > /dev/null 2>&1
    return $?
}

pushd ${BIN_DIR}/.. > /dev/null

if [[ `ls *.jar | wc -w` -ne 1 ]]
then
    logError "The root folder must contain only one .jar file to detect app name. Current file(s) are (`ls *.jar`)"
    exit 1
fi

source ./bin/springboot-config.sh

logInfo "Loading options."
logInfo "These options can be overwrite in bin/springboot-config.sh."
logInfo "========"

for OPTION in ${OPTIONS_NAMES}; do
    echo -n "                    "
    eval echo ${OPTION}='${'${OPTION}'}'
done

case $1 in
start)
    start
;;
stop)
    stop
;;
restart)
    stop ignore
    start
;;
status)
    status
;;
*)
    logError "accepted command: start|stop|restart|status"
    exit 1
;;
esac
exit 0
