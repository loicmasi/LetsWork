.PHONY: bootstrap adapter project open build test

# M0 : l'adaptateur média n'est pas encore intégré au projet (voir SETUP.md, section 5).
bootstrap: project

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
