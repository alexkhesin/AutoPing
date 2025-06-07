import SwiftUI
import RingBuffer
import SimplePing

enum PingStatus {
  case success
  case failure
  case pending
}

// class and not struct because need to return this from RingBufer
// and update the member variables.
class PingData {
  let seq: UInt16?
  var status: PingStatus
  var msec: Int = 0
  
  init(seq: UInt16?, status: PingStatus) {
    self.seq = seq
    self.status = status
  }
}

class PingManager : NSObject {
  static let window = 30 // seconds of memory
  static let windowFailureAveraging = 10  // compute moving average for failures using this window
  static let pingInterval = 1.0  // seconds
  // moving window over window*pingInterval seconds
  let ringBuffer = RingBuffer<PingData>(Int(Double(window) / pingInterval))
  
  let pingDisplay: PingDisplay
  
  var pinger: SimplePing!
  var timer: Timer?
  var maxSeq: UInt16 = 0

  init(_ pingDisplay: PingDisplay, _ hostName: String) {
    self.pingDisplay = pingDisplay
    
    super.init()
    
    AppDelegate.log.info("start \(hostName)")
    pinger = SimplePing(hostName: hostName)
    
    // By default we use the first IP address we get back from host resolution (.Any)
    // but these flags let the user override that.
    
    // Hard-code IPv4 for now, IPv6 does not yet work (packet parsing is the first problem)
    pinger.addressStyle = .icmPv4
    
    pinger.delegate = self
    pinger.start()
  }
  
  // Cannot leave this to deinit because both have references to this object
  func stop() {
    self.pinger.stop()
    self.pinger = nil
    
    self.timer?.invalidate()
    self.timer = nil
  }
  
  // MARK: utilities
  
  // From https://developer.apple.com/library/archive/samplecode/SimplePing/Listings/iOSApp_MainViewController_swift.html
  /// Returns the string representation of the supplied address.
  /// - parameter address: Contains a `(struct sockaddr)` with the address to render.
  /// - returns: A string representation of that address.
  static func displayAddressForAddress(address: Data) -> String {
    var hostStr = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    let nsAddr = address as NSData
    let success = getnameinfo(
      nsAddr.bytes.assumingMemoryBound(to: sockaddr.self),
      socklen_t(nsAddr.length),
      &hostStr, socklen_t(hostStr.count), nil, 0, NI_NUMERICHOST) == 0
    let result: String
    if success {
      result = String(validatingUTF8: hostStr)!
    } else {
      result = "?"
    }
    return result
  }
  
  // from https://developer.apple.com/forums/thread/109355
  func printAddresses() {
    var addrList : UnsafeMutablePointer<ifaddrs>?
    guard
      getifaddrs(&addrList) == 0,
      let firstAddr = addrList
    else { return }
    defer { freeifaddrs(addrList) }
    for cursor in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
      let interfaceName = String(cString: cursor.pointee.ifa_name)
      let addrStr: String
      var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      if let addr = cursor.pointee.ifa_addr,
         getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST) == 0,
         hostname[0] != 0
      {
        addrStr = String(cString: hostname)
      } else {
        addrStr = "?"
      }
      print(interfaceName, addrStr)
    }
    return
  }
  
  // (From https://developer.apple.com/library/archive/samplecode/SimplePing/Listings/iOSApp_MainViewController_swift.html)
  /// Returns a short error string for the supplied error.
  /// - parameter error: The error to render.
  /// - returns: A short string representing that error.
  static func shortErrorFromError(error: NSError) -> String {
    if error.domain == kCFErrorDomainCFNetwork as String && error.code == Int(CFNetworkErrors.cfHostErrorUnknown.rawValue) {
      if let failureObj = error.userInfo[kCFGetAddrInfoFailureKey as String] {
        if let failureNum = failureObj as? NSNumber {
          if failureNum.intValue != 0 {
            let f = gai_strerror(Int32(failureNum.intValue))
            if f != nil {
              return String(validatingUTF8: f!)!
            }
          }
        }
      }
    }
    if let result = error.localizedFailureReason {
      return result
    }
    return error.localizedDescription
  }
  
  private func showPingInfo() {
    pingDisplay.showPingData(avg: average(), percentFailed: percentFailed())
  }
  
  static func makePacket(_ val: UInt64) -> Data {
    return withUnsafeBytes(of: val) { Data($0) }
  }
  static func parsePacket(_ data: Data) -> UInt64 {
    return data.withUnsafeBytes { $0.load(as: UInt64.self) }
  }
  
  // Return -1 if cannot find successful pings.
  // computes weighted moving average https://en.wikipedia.org/wiki/Moving_average#Weighted_moving_average
  func average() -> Int {
    var cnt = 0
    var sum = 0
    for e in ringBuffer {
      if e.status == PingStatus.success {
        cnt += 1
        sum += e.msec * cnt
      }
    }
    return cnt == 0 ? -1 : Int(Double(sum) / Double(cnt * (cnt + 1) / 2))
  }
  
  // Count failures using weighted moving average over buckets
  // of windowFailureAveraging. So the first windowFailureAveraging contribute 1, the next
  // -- 2, etc.
  func percentFailed() -> Int {
    var failed = 0
    var pending = 0
    var cnt = 0
    for (i, e) in ringBuffer.enumerated() {
      let weighted_average_factor = i / PingManager.windowFailureAveraging + 1;
      cnt += 1 * weighted_average_factor
      switch e.status {
      case .failure:
        failed += 1 * weighted_average_factor
      case .pending:
        // Count all pings not responded within 5 seconds as missing
        if (e.seq != nil && Int(maxSeq) - Int(e.seq!) >  Int(PingManager.pingInterval * 5)) {
          pending += 1 * weighted_average_factor
        }
      case .success: break
      }
    }
    if (pending + failed > 0) {
      AppDelegate.log.info("pending \(pending) failed \(failed), total \(self.ringBuffer.count())")
    }
    return Int(Double(failed + pending) * 100 / Double(cnt))
  }
  
  func sendPing() {
    let start_nano: UInt64 = DispatchTime.now().uptimeNanoseconds
    self.pinger.send(with: PingManager.makePacket(start_nano))
  }

  func findPingData(_ seq:UInt16) -> PingData? {
    for e in ringBuffer {
      if e.seq == seq { return e }
    }
    AppDelegate.log.info("seq #\(seq) is too old")
    return nil
  }
}

// MARK: - callbacks for SimplePing library
extension PingManager {
  func startSucceded(_ address: Data) {
    AppDelegate.log.info("pinging \(PingManager.displayAddressForAddress(address: address))")
        
    // Send the first ping straight away.
    self.sendPing()
        
    // And start a timer to send the subsequent pings.
    self.timer = Timer.scheduledTimer(withTimeInterval: PingManager.pingInterval, repeats: true) { timer in
      self.sendPing()
    }
  }
  func startFailed(_ error: Error) {
    AppDelegate.log.warning("failed: \(PingManager.shortErrorFromError(error: error as NSError))")
        
    ringBuffer.put(PingData(seq: nil, status: .failure))
    showPingInfo()
        
    // Retry starting
    timer = Timer.scheduledTimer(timeInterval: PingManager.pingInterval, target: pinger!, selector: #selector(SimplePing.start), userInfo: nil, repeats: false)
  }
  
  func sent(_ packet: Data, _ sequenceNumber: UInt16) {
    maxSeq = sequenceNumber
    ringBuffer.put(PingData(seq: sequenceNumber, status: .pending))
    showPingInfo()
    AppDelegate.log.debug("seq #\(sequenceNumber) sent")
  }
  func sendFailed(_ packet: Data, _ sequenceNumber: UInt16, _ error: Error) {
    AppDelegate.log.warning("seq #\(sequenceNumber) send failed \(PingManager.shortErrorFromError(error: error as NSError))")
    ringBuffer.put(PingData(seq: sequenceNumber, status: .failure))
    showPingInfo()
  }
  func received(_ packet: Data, _ sequenceNumber: UInt16) {
    let sz = MemoryLayout<ICMPHeader>.size
    /*
    -- if we need to look at ICMPHeader ever
    let icmp_header = packet.prefix(sz).withUnsafeBytes{ buffer in
      buffer.load(as: ICMPHeader.self)}
    */
    let response = packet.suffix(from: sz)
    if (response.count != 8) {
      AppDelegate.log.error("wrong response size: \(sequenceNumber) received, size=\(response.count)")
      return
    }
    let start_nano = PingManager.parsePacket(response)
    let end_nano : UInt64 = DispatchTime.now().uptimeNanoseconds
    let diff_nano = (end_nano - start_nano);
    let diff_msec = Int(Double(diff_nano) / 1e6)
    AppDelegate.log.debug("seq #\(sequenceNumber) received, size=\(response.count) msec=\(diff_msec)")

    let pd = findPingData(sequenceNumber)
    AppDelegate.log.debug("found seq #\(sequenceNumber) \(pd != nil)")
    pd?.msec = diff_msec
    pd?.status = PingStatus.success
    showPingInfo()
  }
  func unexpected(_ packet: Data) {
    // Get this when a parallel ping is running since ICMP seems to get delivered to all sockets???
    // I think it is completely fine to just ignore these
    AppDelegate.log.debug("unexpected packet, size=\(packet.count)")
  }
}

// Adapt all the overloaded callbacks from SimplePing library to have meaningful names
extension PingManager: SimplePingDelegate {
  private func checkPinger(_ pinger: SimplePing) -> Bool {
    if (pinger != self.pinger) {
      AppDelegate.log.error("Stale")
      return false
    }
    return true
  }
  
  func simplePing(_ pinger: SimplePing, didStartWithAddress address: Data) {
    if (!checkPinger(pinger)) { return }
    startSucceded(address)
  }
  
  func simplePing(_ pinger: SimplePing, didFailWithError error: Error) {
    if (!checkPinger(pinger)) { return }
    startFailed(error)
  }
    
  func simplePing(_ pinger: SimplePing, didSendPacket packet: Data, sequenceNumber: UInt16) {
    if (!checkPinger(pinger)) { return }
    sent(packet, sequenceNumber)
  }
    
  func simplePing(_ pinger: SimplePing, didFailToSendPacket packet: Data, sequenceNumber: UInt16, error: Error) {
    if (!checkPinger(pinger)) { return }
    sendFailed(packet, sequenceNumber, error)
  }
    
  func simplePing(_ pinger: SimplePing, didReceivePingResponsePacket packet: Data, sequenceNumber: UInt16) {
    if (!checkPinger(pinger)) { return }
    received(packet, sequenceNumber);
  }
    
  func simplePing(_ pinger: SimplePing, didReceiveUnexpectedPacket packet: Data) {
    if (!checkPinger(pinger)) { return }
    unexpected(packet)
  }
}
