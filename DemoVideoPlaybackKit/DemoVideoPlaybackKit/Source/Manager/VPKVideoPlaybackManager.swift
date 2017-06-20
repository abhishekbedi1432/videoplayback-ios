//
//  VPKVideoPlayerManager.swift
//  VideoPlaybackKit
//
//  Created by Sonam on 4/21/17.
//  Copyright © 2017 ustwo. All rights reserved.
//

import Foundation
import AVKit
import AVFoundation
import RxSwift


class VPKVideoPlaybackManager: NSObject, VPKVideoPlaybackManagerProtocol {
    
    
    weak var delegate: VPKVideoPlaybackDelegate?
    static let shared = VPKVideoPlaybackManager()
    
    //state
    var playerState: PlayerState?
    var currentVideoUrl: URL?
    var isPlaying: Bool {
        return self.isPlayerPlaying()
    }
    
    //output
    var onStartPlayingWithDurationClosure: StartWithDurationClosure?
    var onStopPlayingClosure: CompletionClosure?
    var onDidPlayToEndClosure: CompletionClosure?
    var onPlayerLayerClosure: LayerClosure?
    var onTimeDidChangeClosure: TimeClosure?
    
    //private
    fileprivate var isSeekInProgress = false
    fileprivate var chaseTime = kCMTimeZero
    fileprivate static let queueIdentifier = "com.vpk.playerQueue"
    fileprivate lazy var player = AVPlayer()
    fileprivate enum ObservableKeyPaths: String {
        case status, rate, timeControlStatus
        static let allValues = [status, rate, timeControlStatus]
    }

    //MARK: Setup
    override init() {
        super.init()
        playerState = .paused
        player.actionAtItemEnd = .none
      //  addApplicationObservers()
        trackTimeProgress()
        addPlayerObservers()
    }
    
    fileprivate func playVideoForTheFirstTime(_ url: URL) {
        let serviceGroup = DispatchGroup()
        let backgroundQueue = DispatchQueue(label: VPKVideoPlaybackManager.queueIdentifier, qos: .background, target: nil)
        
        
        let workItemOne = DispatchWorkItem {
            serviceGroup.enter()
            serviceGroup.notify(queue: DispatchQueue.main, execute: {
                //   self.currentInteractor?.resetPresentation()
                
              //  self.delegate?.playbackManagerDidPlayNewVideo(self)
                //self.reset()
                
            })
            serviceGroup.leave()
        }
        
        backgroundQueue.async(execute: workItemOne)
        serviceGroup.notify(queue: backgroundQueue, work: workItemOne)
        
        //Player Asset + Layer setup
        let workItemTwo = DispatchWorkItem {
            let playerAsset = AVAsset(url: url)
            let playerItem = AVPlayerItem(asset: playerAsset)
            self.currentVideoUrl = url
            let playerLayer = AVPlayerLayer(player: self.player)
            
            serviceGroup.notify(queue: DispatchQueue.main, execute: {
                self.didPreparePlayerLayer(playerLayer)
                self.play()
                self.configurePlayer(item: playerItem)
                self.addPlayerItemObservers()
            })
        }
        
        serviceGroup.notify(queue: backgroundQueue, work: workItemTwo)
        backgroundQueue.async(group: serviceGroup, execute: workItemTwo)
    }

    
    //MARK: Configuration
    fileprivate func configurePlayer(item: AVPlayerItem?) {
        let queue = DispatchQueue(label: "item_exchange")
        queue.async {
            self.player.replaceCurrentItem(with: item)
        }
    }
    
    //MARK: Playback 
    public func stop() {
        player.pause()
    }
    
    fileprivate func play() {
        player.play()
        player.rate = 1.0 // sets desired playback rate (full speed)
    }
    
    
    //MARK: KVO setup
    fileprivate func trackTimeProgress() {
        player.addPeriodicTimeObserver(forInterval: CMTimeMake(1, 2), queue: DispatchQueue.main) { [weak self] (time) in
            self?.videoPlayingTimeChangedTo(time.seconds)
        }
    }
    
    private func addPlayerObservers() {
        player.addObserver(self, forKeyPath: ObservableKeyPaths.status.rawValue, options: .new, context: nil)
        player.addObserver(self, forKeyPath: ObservableKeyPaths.rate.rawValue, options: .new, context: nil)
        player.addObserver(self, forKeyPath: ObservableKeyPaths.timeControlStatus.rawValue, options: .new, context: nil)
    }
    
    private func addPlayerItemObservers() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: self.player.currentItem, queue: nil) { (notification) in
            self.didPlayToEnd()
        }
    }
    
    private func removePlayerObservers() {
        player.removeObserver(self, forKeyPath: ObservableKeyPaths.status.rawValue)
        player.removeObserver(self, forKeyPath: ObservableKeyPaths.rate.rawValue)
        player.removeObserver(self, forKeyPath: ObservableKeyPaths.timeControlStatus.rawValue)
    }
    
    fileprivate func removePlayerItemObservers() {
        if player.currentItem != nil {
            let itemQueue = DispatchQueue(label: "com.vpk.playerItemQueue", qos: .background, attributes: DispatchQueue.Attributes.concurrent, autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.inherit, target: nil)
            itemQueue.async {
                NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: self.player.currentItem)
                self.configurePlayer(item: nil)
            }
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard   let key = keyPath,
            let keyPathEnumType: ObservableKeyPaths = ObservableKeyPaths(rawValue: key) else { return }
        
        switch keyPathEnumType {
        case .timeControlStatus:
            handleObservedTimeControlStatus()
        case .rate where player.rate == 0:
            didStopPlaying()
        case .rate where player.rate == 1:
            if #available(iOS 10.0, *) { /* handled with time control status  */ break } else {
                didStartPlaying()
            }
        default:
            break
        }
    }
    
    func handleObservedTimeControlStatus() {
        if #available(iOS 10.0, *) {
            let timeStatus = player.timeControlStatus
            switch timeStatus {
            case AVPlayerTimeControlStatus.playing:
                didStartPlaying()
            default:
                break
            }
        }
    }

    //MARK: Helpers
    func isPlayerPlaying() -> Bool {
        return player.rate == 1 && player.error == nil
    }
    
    deinit {
        removePlayerObservers()
    }
}

extension VPKVideoPlaybackManager: VPKVideoPlaybackManagerOutputProtocol {
    
    fileprivate func didPreparePlayerLayer(_ playerLayer: AVPlayerLayer) {
        delegate?.playbackManager(self, didPreparePlayerLayer: playerLayer)
        //onPlayerLayerClosure?(playerLayer)
    }
    
    fileprivate func didStopPlaying() {
        #if DEBUG
            print("stopped playing")
        #endif
            
        playerState = .paused
        //onStopPlayingClosure?()
        delegate?.playbackManagerDidStopPlaying(self)
    }
    
    fileprivate func didStartPlaying() {
        #if DEBUG
            print("started playing")
        #endif
        
        guard let duration = player.currentItem?.asset.duration,
            let transformedTime = CMTimeGetSeconds(duration) as? Double else {
                #if DEBUG
                    print("error getting player asset duration")
                #endif
            return
        }
        
        playerState = .playing
        //onStartPlayingWithDurationClosure?(TimeInterval(transformedTime))
        delegate?.playbackManager(self, didStartPlayingWithDuration: transformedTime)
    }
    
    fileprivate func didPlayToEnd() {
        playerState = .paused
        configurePlayer(item: nil)
        //onDidPlayToEndClosure?()
        delegate?.playbackManagerDidPlayToEnd(self)
    
    }
    
    fileprivate func videoPlayingTimeChangedTo(_ time: TimeInterval) {
        //onTimeDidChangeClosure?(time)
        delegate?.playbackManager(self, didChangePlayingTime: time)
    }
}

extension VPKVideoPlaybackManager: VPKVideoPlaybackManagerInputProtocol {
    
    func didScrubTo(_ seconds: TimeInterval) {
        #if DEBUG
            print("USER SCRUBBED VIDEO TO \(seconds)")
        #endif
        stopPlayingAndSeekSmoothlyToTime(newChaseTime: CMTimeMakeWithSeconds(seconds, 1))
    }
    
    func didReuseInVideoCell() {
        if isPlayerPlaying() {
          cleanup()
        }
    }
    
    func didMoveOffScreen()  {
        if isPlayerPlaying() {
            player.pause()
        }
    }
    
    func didSelectVideoUrl(_ url: URL) {
        //TODO: REFACTOR
        guard let state = playerState else { return }
        switch state {
        case .paused where currentVideoUrl == nil:
            playVideoForTheFirstTime(url)
        case .playing where url == currentVideoUrl:
            stop()
        case .playing where url != currentVideoUrl, .paused where url != currentVideoUrl:
            cleanup()
            playVideoForTheFirstTime(url)
        case .paused where url == currentVideoUrl:
            play()
        default:
            break
        }
    }
    
    func cleanup() {
        stop()
        configurePlayer(item: nil)
        removePlayerItemObservers()
        delegate?.playbackManagerDidPlayNewVideo(self)
    }
}

//MARK: Time Scrubbing
extension VPKVideoPlaybackManager {
    
    func stopPlayingAndSeekSmoothlyToTime(newChaseTime: CMTime) {
        player.pause()
        if CMTimeCompare(newChaseTime, chaseTime) != 0 {
            chaseTime = newChaseTime
            if !isSeekInProgress {
                trySeekToChaseTime()
            }
        }
    }
    
    fileprivate func trySeekToChaseTime() {        
        if player.currentItem?.status == .unknown {
            // wait until item becomes ready (KVO player.currentItem.status)
        } else if player.currentItem?.status  == .readyToPlay {
            actuallySeekToTime()
        }
    }
    
    fileprivate func actuallySeekToTime() {
        isSeekInProgress = true
        let seekTimeInProgress = chaseTime
        player.seek(to: seekTimeInProgress, toleranceBefore: kCMTimeZero,
                    toleranceAfter: kCMTimeZero, completionHandler:
            { (isFinished) -> () in
                if CMTimeCompare(seekTimeInProgress, self.chaseTime) == 0 {
                    self.isSeekInProgress = false
                    self.play()
                }
                else {
                    self.trySeekToChaseTime()
                }
        })
    }
}