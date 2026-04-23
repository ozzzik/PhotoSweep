# Regenerate Xcode project and integrate CocoaPods. Always open PhotosCleanup.xcworkspace (not .xcodeproj).

.PHONY: project
project:
	xcodegen generate
	pod install
	@echo "Open PhotosCleanup.xcworkspace in Xcode."
