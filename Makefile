.PHONY: bootstrap adapter project open build test

bootstrap: adapter project

adapter:
	./scripts/build-mediaremote-adapter.sh

project:
	xcodegen generate

open: project
	open LetsWork.xcodeproj

build: project
	xcodebuild -project LetsWork.xcodeproj -scheme LetsWork -configuration Debug build

test: project
	xcodebuild -project LetsWork.xcodeproj -scheme LetsWork test
