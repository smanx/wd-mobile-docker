IMAGE   := wd-server
CONTAINER := wd-server

.PHONY: image run run-host status shell game-start game-stop stop clean

## 构建镜像（自动先合并 server/wd-parts 分卷为 wd.zip，约 10-20 分钟）
image:
	bash server/assemble-wdzip.sh
	docker build -f docker/Dockerfile -t $(IMAGE):latest .

## 运行（bridge + 端口映射 + 持久化数据卷）
run:
	docker run -d --name $(CONTAINER) \
	  --restart unless-stopped --shm-size=1g \
	  -v wd-mysql-data:/var/lib/mysql \
	  -p 81:81 -p 80:80 -p 443:443 -p 88:88 -p 9877:9877 -p 3306:3306 -p 6379:6379 \
	  -p 10001-10310:10001-10310 \
	  -e AUTO_START_GAME=1 \
	  $(IMAGE):latest

## 停止并删除容器
stop:
	-docker stop $(CONTAINER) && docker rm $(CONTAINER)

## 体检
status:
	bash tests/healthcheck.sh

shell:
	docker exec -it $(CONTAINER) bash

## 手动启动/停止游戏进程（容器内）
game-start:
	docker exec -d $(CONTAINER) /home/s1/qd
	docker exec -d $(CONTAINER) sh -c 'cd /home/daili && sh ry.sh start'

game-stop:
	docker exec $(CONTAINER) /home/s1/stop

clean: stop
	-docker rmi $(IMAGE):latest
