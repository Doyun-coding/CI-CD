JAVA_PATH="/usr/local/java/java21/bin/java"
TARGET_DIR=~/target
LOG_DIR=~/logs

export GIT_PRIVATE_KEY="$(cat /home/be9/be9-team2/.ssh/id_rsa)"

mkdir -p "$LOG_DIR"

SERVICE_NAME=$1

# cicd.yml 에서 이름을 지정하지 않았을 경우 exit
if [[ -z "$SERVICE_NAME" ]]; then
  exit 1
fi

# 포트 매핑
case "$SERVICE_NAME" in
#       eureka) OLD_PORT=10230 ; NEW_PORT=10231;;
        gateway) OLD_PORT=10232 ; NEW_PORT=10233;;
        auth) OLD_PORT=10234 ; NEW_PORT=10235;;
        back) OLD_PORT=10236 ; NEW_PORT=10237;;
        front) OLD_PORT=10238 ; NEW_PORT=10239;;
        config) OLD_PORT=10240 ; NEW_PORT=10241;;
        *)
                echo "unsupported service name: $SERVICE_NAME"
                exit 1
                ;;
esac

# jar 및 로그 경로
JAR_PATH=$(ls "$TARGET_DIR"/${SERVICE_NAME}-*.jar 2>/dev/null | head -n 1)
LOG_PATH1="$LOG_DIR/${SERVICE_NAME}Log1"
LOG_PATH2="$LOG_DIR/${SERVICE_NAME}Log2"

# JAR 파일이 없는 경우
if [[ ! -f "$JAR_PATH" ]]; then
  ls -al "$TARGET_DIR"
  exit 1
fi

EUREKA_HOST=s1.java21.net
EUREKA_PORT=10230

# EUREKA에 죽인다는 사실을 알리고 EUREKA는 해당 포트를 죽인다
if [[ -n "$NEW_PORT" ]]; then
  APP_NAME=$(echo "$SERVICE_NAME" | tr '[:lower:]' '[:upper:]') # 소문자를 대문자로 변환
  INSTANCE_ID="$(hostname):$SERVICE_NAME:$NEW_PORT"

  echo "NEW_PORT 죽이기 알리기";

  curl -s -X PUT "http://$EUREKA_HOST:$EUREKA_PORT/eureka/apps/$APP_NAME/$INSTANCE_ID/status?value=OUT_OF_SERVICE" \
       -H "Content-Type: application/json"

  echo "NEW_PORT 죽이기 종료";

fi

sleep 30

# NEW_PORT 죽임
if [[ -n "$NEW_PORT" ]]; then
  NEW_PID=$(lsof -t -i:$NEW_PORT)
  if [[ -n "$NEW_PID" ]]; then
    kill -15 $NEW_PID

    echo "NEW_PORT 죽이기 완료";

    sleep 5
    fi
fi

# 지정 포트 할당
nohup $JAVA_PATH -Dspring.profiles.active=prod -Dserver.port=$NEW_PORT -jar "$JAR_PATH" > "$LOG_PATH1" 2>&1 &

NEW_PID=$!

echo "NEW_PORT 헬스 체크 시작";

# 헬스체크 (30초)
for i in {1..10}; do
  STATUS=$(curl -s "http://127.0.0.1:$NEW_PORT/actuator/health" | grep '"status":"UP"')
  if [[ -n "$STATUS" ]]; then
    break
  fi
  sleep 3
done

# 헬스체크 실패 시 비정상 인스턴스 즉시 종료
if [[ -z "$STATUS" ]]; then

  echo "헬스체크 실패";

  kill -9 $NEW_PID
  exit 1
fi

# EUREKA에 OLD_PORT 죽인다는 사실을 알리 EUREKA는 해당 포트를 죽인다
if [[ -n "$OLD_PORT" ]]; then
  APP_NAME=$(echo "$SERVICE_NAME" | tr '[:lower:]' '[:upper:]')
  INSTANCE_ID="$(hostname):$SERVICE_NAME:$NEW_PORT"

  echo "OLD_PORT 죽이기 시작";

  curl -s -X PUT "http://$EUREKA_HOST:$EUREKA_PORT/eureka/apps/$APP_NAME/$INSTANCE_ID/status?value=OUT_OF_SERVICE" \
       -H "Content-Type: application/json"

  echo "OLD_PORT 죽이기 종료";

fi

sleep 30
# OLD_PORT 죽임
if [[ -n "$OLD_PORT" ]]; then
  OLD_PID=$(lsof -t -i:$OLD_PORT)
  if [[ -n "$OLD_PID" ]]; then
    kill -15 $OLD_PID

    echo "OLD_PORT 죽임";

    sleep 5
  fi
fi

sleep 3

nohup $JAVA_PATH -Dspring.profiles.active=prod -Dserver.port=$OLD_PORT -jar "$JAR_PATH" > "$LOG_PATH2" 2>&1 &

echo "OLD_PORT 실행";

echo "OLD_PORT 헬스 체크 시작";

for i in {1..10}; do
  STATUS=$(curl -s "http://127.0.0.1:$OLD_PORT/actuator/health" | grep '"status":"UP"')
  if [[ -n "$STATUS" ]]; then
    break
  fi
  sleep 3
done

if [[ -z "$STATUS" ]]; then
  kill -9 $NEW_PID

  echo "헬스체크 실패";

  exit 1
fi

# 기존 인스턴스 종료
# if [[ -n "$OLD_PORT" ]]; then
  # OLD_PID=$(lsof -t -i:$OLD_PORT)
  # if [[ -n "$OLD_PID" ]]; then
    # kill -15 $OLD_PID
    # sleep 5
  # fi
# fi

echo "헬스체크 성공"

sleep 3
tail -n 10 "$LOG_PATH"

echo "성공적 종료";