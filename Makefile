CLT_DEV := /Library/Developer/CommandLineTools/Library/Developer
TEST_FLAGS := -Xswiftc -F$(CLT_DEV)/Frameworks \
              -Xlinker -F$(CLT_DEV)/Frameworks \
              -Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks \
              -Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib
VERSION ?= 0.1.0

.PHONY: build test test-integration app run zip clean

build:
	swift build -c release

test:
	swift test $(TEST_FLAGS) --skip WhisperKitEngineIntegrationTests

test-integration:
	TRANSCRIPTOR_INTEGRATION=1 swift test $(TEST_FLAGS) --filter WhisperKitEngineIntegrationTests

app: build
	VERSION=$(VERSION) scripts/make-app.sh

run: app
	open dist/Transcriptor.app

zip: app
	ditto -c -k --keepParent dist/Transcriptor.app dist/Transcriptor-$(VERSION).zip

clean:
	rm -rf .build dist
