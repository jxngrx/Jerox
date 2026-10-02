DERIVED := build/DerivedData
APP     := $(DERIVED)/Build/Products/Debug/Jerox.app
XCODE   := xcodebuild -project Jerox.xcodeproj -scheme Jerox -configuration Debug -derivedDataPath $(DERIVED)

# Pure-Foundation logic, compiled on its own with its self-checks (no Xcode, no signing).
LOGIC := Jerox/Clipboard/Clip.swift Jerox/Clipboard/ClipboardHistory.swift \
         Jerox/Clipboard/PasteTransforms.swift Jerox/Clipboard/ClipClassifier.swift \
         Jerox/Rephrase/RephrasePrompts.swift Jerox/Rephrase/AIProviders.swift \
         Jerox/Dictation/DictationText.swift Jerox/ScreenText/ScreenTextLayout.swift

.PHONY: build run test ci clean

build:
	$(XCODE) build

run: build
	-pkill -x Jerox
	open $(APP)

test:
	@mkdir -p build
	swiftc -D JEROX_CHECK -parse-as-library $(LOGIC) -o build/jerox-check
	build/jerox-check && echo "self-check passed"

ci: test
	$(XCODE) CODE_SIGNING_ALLOWED=NO build

clean:
	rm -rf build
