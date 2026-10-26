.PHONY: bootstrap adapter project open build test run

# Un seul emplacement de build, pour ne jamais lancer une copie périmée de l'app.
DERIVED_DATA := build/DerivedData
APP := $(DERIVED_DATA)/Build/Products/Debug/LetsWork.app

bootstrap: adapter project

adapter:
	./scripts/build-mediaremote-adapter.sh

project:
	xcodegen generate

open: project
	open LetsWork.xcodeproj

build: project
	xcodebuild -project LetsWork.xcodeproj -scheme LetsWork -configuration Debug -derivedDataPath $(DERIVED_DATA) build

test: project
	xcodebuild -project LetsWork.xcodeproj -scheme LetsWork -derivedDataPath $(DERIVED_DATA) test

# Compile, quitte l'instance en cours (quelle que soit sa copie) et lance ce build.
run: build
	-pkill -x LetsWork
	while pgrep -x LetsWork > /dev/null; do sleep 0.1; done
	open "$(APP)"
