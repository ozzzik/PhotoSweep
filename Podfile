# PhotoSweep — CocoaPods (run after `xcodegen generate`: `pod install`, open PhotosCleanup.xcworkspace)
# Unity Ads = primary; Google Mobile Ads (AdMob) = fallback when Unity has no fill or after your account is restored.

platform :ios, '17.0'
use_frameworks! :linkage => :static

target 'PhotosCleanup' do
  project 'PhotosCleanup.xcodeproj'

  pod 'UnityAds', '~> 4.12'
  pod 'Google-Mobile-Ads-SDK', '~> 12.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    end
  end
end
