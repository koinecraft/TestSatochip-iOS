//
//  CardData.swift
//  Satodime
//
//  Created by Satochip on 01/12/2023.
//

import Foundation
import Combine
import CoreNFC
import SatochipSwift
import CryptoSwift
//import MnemonicSwift
//import SwiftUI
//import XCTest

enum SatocardError: Error {
    case testError(String)
    case randomGeneratorError
}

class CardState: ObservableObject {
    let log = LoggerService.shared
    var cmdSet: SatocardCommandSet!
    var cardStatus: CardStatus!
    var isCardDataAvailable = false
    var authentikeyHex = ""

    // certificate
    var certificateDic = ["":""]
    var certificateCode = PkiReturnCode.unknown
    
    // For NFC session
    var session: SatocardController? // TODO: clean (used with scan())
    // used with the different methods to perform actions on the card
    var cardController: SatocardController?
    
    // test
    var nbTestTotal = 0
    var nbTestSuccess = 0
    
    func hasReadCard() -> Bool {
        return isCardDataAvailable
    }
    
    // TODO: put in SatochipSwift.CardStatus
    func getCardVersionInt(cardStatus: CardStatus) -> Int {
        return Int(cardStatus.protocolMajorVersion) * (1<<24) +
                Int(cardStatus.protocolMinorVersion) * (1<<16) +
                Int(cardStatus.appletMajorVersion) * (1<<8) +
                Int(cardStatus.appletMinorVersion)
    }
    
    func scan(){
        print("CardState scan()")
        DispatchQueue.main.async {
            self.certificateCode = PkiReturnCode.unknown
            self.authentikeyHex = ""
            self.isCardDataAvailable = false

        }
        session = SatocardController(onConnect: onConnection, onFailure: onDisconnection)
        session?.start(alertMessage: "Scan your card")
    }
    
    //Card connection
    func onConnection(cardChannel: CardChannel) -> Void {
        log.info("Start card reading", tag: "CardState.onConnection")
        cmdSet = SatocardCommandSet(cardChannel: cardChannel)
        let parser = SatocardParser()
        
        do {
            // var (rapdu, cardType) = try cmdSet.selectApplet(cardType: CardType.anycard)
            var (rapdu, cardType) = try cmdSet.selectApplet(cardType: CardType.satochip)    // Just select Satochip applet
            log.info("cardType: \(cardType)", tag: "CardState.onConnection")
            let statusApdu = try cmdSet.cardGetStatus()
            cardStatus = try CardStatus(rapdu: statusApdu)
            log.info("cardStatus: \(cardStatus)", tag: "CardState.onConnection")
          
            switch (cardType) {
            case .satodime:
                testSatodime()
            case .seedkeeper:
                try testSeedkeeper()
            case .satochip:
                try testSatochip()
            default:
                log.warning("Unexpected cardType: \(cardType)", tag: "CardState.onConnection")
            }
            
            // check if setupDone
            if cardStatus.setupDone == false {
                
                // check version: v0.1-0.1 cannot proceed further without setup first
                print("DEBUG CardVersionInt: \(getCardVersionInt(cardStatus: cardStatus))")
                if getCardVersionInt(cardStatus: cardStatus) <= 0x00010001 {
                    session?.stop(alertMessage: String(localized: "nfcSatodimeNeedsSetup"))
                    log.warning("Satodime v0.1-0.1 requires user to claim ownership to continue!", tag: "CardState.onConnection")
                    // dispatchGroup is used to wait for scan() to finish before fetching web api
                    //dispatchGroup.leave()
                    return
                }
            }
            
            // check Card authenticity
            do {
                let (certificateCode, certificateDic) = try cmdSet.cardVerifyAuthenticity()
                if certificateCode == .success {
                    log.info("Card authenticated successfully!", tag: "CardState.onConnection")
                } else {
                    log.warning("Failed to authenticate card with code: \(certificateCode)", tag: "CardState.onConnection")
                }
                DispatchQueue.main.async {
                    self.certificateCode = certificateCode
                    self.certificateDic = certificateDic
                }
            } catch {
                log.error("Failed to authenticate card with error: \(error)", tag: "CardState.onConnection")
            }
            
            // get authentikey
            let (_, _, authentikeyHex) = try cmdSet.cardGetAuthentikey()
            DispatchQueue.main.async {
                self.authentikeyHex = authentikeyHex
            }
            log.info("authentikeyHex: \(authentikeyHex)", tag: "CardState.onConnection")
            
            DispatchQueue.main.async {
              self.isCardDataAvailable = true
            }
            
            session?.stop(alertMessage: String(localized: "nfcVaultsListSuccess"))
            log.info(String(localized: "nfcVaultsListSuccess"), tag: "CardState.onConnection")
            
        } catch let error {
            session?.stop(errorMessage: "\(String(localized: "nfcErrorOccured")) \(error.localizedDescription)")
            log.error("\(String(localized: "nfcErrorOccured")) \(error.localizedDescription)", tag: "CardState.onConnection")
            log.error("\(String(localized: "nfcErrorOccured")) \(error)", tag: "CardState.onConnection")
        }
        
        //dispatchGroup.leave()
        
    } // end onConnection
    
    // MARK: SATODIME
    public func testSatodime(){
        log.info("Start Satodime tests", tag: "CardState.testSatodime")
    }
    
    
    // MARK: SEEDKEEPER
    public func testSeedkeeper() throws {
        log.info("Start Seedkeeper tests", tag: "CardState.testSeedkeeper")
        
        let pinString = "123456"
        let pinBytes = Array("123456".utf8)
        let wrongPinBytes = Array("0000".utf8)
        var rapdu = APDUResponse(sw1: 0x00, sw2: 0x00, data: [])
        
        // applet version
        let appletVersion = cardStatus.protocolVersion
        
        // check setup status
        let setupDone = cardStatus.setupDone
        if (!setupDone){
            do {
                rapdu = try cmdSet.cardSetup(pin_tries0: 5, pin0: pinBytes)
            } catch let error {
                log.warning("Error: \(error)", tag:"CardState.testSeedkeeper")
            }
        }
        
        // verify PIN
        try cmdSet.cardVerifyPIN(pin: pinBytes)
        
        //Test
        //do {try testGenerateMasterseed()}
        //do {try testGenerateRandomSecret()}
        //do {try testImportExportSecretPlain()}
        //do {try testImportExportSecretEncrypted()}
        //do {try testBip39MnemonicV2()}
        //do {try testCardBip32GetExtendedkeySeedVector1()}
        //do {try testCardBip32GetExtendedkeySeedVector2()}
        //do {try testCardBip32GetExtendedkeySeedVector3()}
        //do {try testCardBip32GetExtendedkeyBip85()}
        do {try testSeedkeeperMemory()}
    }
    
    // MARK: testGenerateMasterseed
    public func testGenerateMasterseed() throws {
        log.info("Start", tag: "CardState.testGenerateMasterseed")
        nbTestTotal+=1
        var sid=0
        for seedSize in stride(from: 16, to: 65, by: 16){
            log.info("seedSize: \(seedSize)", tag: "testGenerateMasterseed")
            
            let exportRights = SeedkeeperExportRights.exportPlaintextAllowed
            let label = "Test masterseed \(seedSize) export-allowed"
            let (rapdu, header) = try cmdSet.seedkeeperGenerateMasterseed(seedSize: seedSize,
                                                                           exportRights: exportRights,
                                                                           label: label)
            try checkEqual(rapdu.sw, StatusWord.ok.rawValue, tag: "testGenerateMasterseed")
            
            // check last log
            var (logs, nbTotalLogs, nbAvailLogs) = try cmdSet.seedkeeperPrintLogs(printAll: false)
            try checkEqual(logs.count, 1, tag: "testGenerateMasterseed")
            var lastLog = logs[0]
            try checkEqual(lastLog.ins, SatocardINS.generateMasterseed.rawValue, tag: "testGenerateMasterseed")
            try checkEqual(lastLog.sid1, header.sid, tag: "testGenerateMasterseed")
            try checkEqual(lastLog.sid2, 0xFFFF, tag: "testGenerateMasterseed")
            try checkEqual(lastLog.sw, StatusWord.ok.rawValue, tag: "testGenerateMasterseed")
            
            // export secret and check fingerprint
            let secretObject =  try cmdSet.seedkeeperExportSecret(sid: header.sid, sidPubkey: nil)
            let exportedHeader = secretObject.secretHeader
            try checkEqual(exportedHeader.sid, header.sid, tag: "testGenerateMasterseed")
            try checkEqual(exportedHeader.type, header.type, tag: "testGenerateMasterseed") //SeedkeeperSecretType.masterseed)
            try checkEqual(exportedHeader.origin, header.origin, tag: "testGenerateMasterseed") //SeedkeeperSecretOrigin.generatedOnCard)
            try checkEqual(exportedHeader.exportRights, header.exportRights, tag: "testGenerateMasterseed")
            try checkEqual(exportedHeader.fingerprintBytes, header.fingerprintBytes, tag: "testGenerateMasterseed")
            try checkEqual(exportedHeader.rfu2, header.rfu2, tag: "testGenerateMasterseed")
            try checkEqual(exportedHeader.subtype, header.subtype, tag: "testGenerateMasterseed")
            try checkEqual(exportedHeader.label, header.label, tag: "testGenerateMasterseed")
                
            // check last log
            (logs, nbTotalLogs, nbAvailLogs) = try cmdSet.seedkeeperPrintLogs(printAll: false)
            try checkEqual(logs.count, 1, tag: "testGenerateMasterseed")
            lastLog = logs[0]
            try checkEqual(lastLog.ins, SatocardINS.exportSecret.rawValue, tag: "testGenerateMasterseed")
            try checkEqual(lastLog.sid1, exportedHeader.sid, tag: "testGenerateMasterseed")
            try checkEqual(lastLog.sid2, 0xFFFF, tag: "testGenerateMasterseed")
            try checkEqual(lastLog.sw, StatusWord.ok.rawValue, tag: "testGenerateMasterseed")
            
            // erase secret if supported
            if cardStatus.protocolVersion >= 0x0002 {
                // test delete
                let rapdu = try cmdSet.seedkeeperResetSecret(sid: header.sid)
                try checkEqual(rapdu.sw, StatusWord.ok.rawValue, tag: "testGenerateMasterseed")
            } else {
                log.info("Seedkeeper v\(cardStatus.protocolVersion): Erasing secret not supported!",
                            tag: "testGenerateMasterseed")
            }
            
        } // for
        nbTestSuccess+=1
    }
    
    // MARK: testGenerateRandomSecret
    public func testGenerateRandomSecret() throws{
        //introduced in Seedkeeper v0.2
        if cardStatus.protocolVersion < 0x0002 {
            log.warning("Seedkeeper v\(cardStatus.protocolVersion): generate random_secret with external entropy not supported!", tag: "testGenerateMasterseed")
            return
        }
        nbTestTotal+=1
        let pwSizes = [16, 32, 48, 64]
        for index in 0..<pwSizes.count {
            let size = pwSizes[index]
            let stype = SeedkeeperSecretType.masterPassword //0x91 # Master Password
            let exportRights = SeedkeeperExportRights.exportPlaintextAllowed //0x01 # Plaintext export allowed
            let subtype = 0x00 // default
            let label = "Test MasterPassword Size: \(size)"

            // random entropy as ascii text
            let entropy = try randomBytes(count: size)
            let saveEntropy = true
            
            // generate on card
            var (rapdu, headers) = try cmdSet.seedkeeperGenerateRandomSecret(stype: stype,
                                                                              subtype: UInt8(subtype),
                                                                              size: UInt8(size),
                                                                              saveEntropy: saveEntropy,
                                                                              entropy: entropy,
                                                                              exportRights: exportRights,
                                                                              label: label)
            
            try checkEqual(rapdu.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
            
            // export master password in plaintext
            let secretHeader = headers[0]
            let secretObject =  try cmdSet.seedkeeperExportSecret(sid: secretHeader.sid, sidPubkey: nil)
            var exportedHeader = secretObject.secretHeader
            try checkEqual(exportedHeader.sid, secretHeader.sid, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedHeader.type, secretHeader.type, tag: "Function: \(#function), line: \(#line)") //SeedkeeperSecretType.masterseed)
            try checkEqual(exportedHeader.origin, secretHeader.origin, tag: "Function: \(#function), line: \(#line)") //SeedkeeperSecretOrigin.generatedOnCard)
            try checkEqual(exportedHeader.exportRights, secretHeader.exportRights, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedHeader.fingerprintBytes, secretHeader.fingerprintBytes, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedHeader.rfu2, secretHeader.rfu2, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedHeader.subtype, secretHeader.subtype, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedHeader.label, secretHeader.label, tag: "Function: \(#function), line: \(#line)")
            // test master password fingerprint
            try checkEqual(secretObject.getFingerprintFromSecret(), secretHeader.fingerprintBytes, tag: "Function: \(#function), line: \(#line)")
            
            // check last log
            var (logs, nbTotalLogs, nbAvailLogs) = try cmdSet.seedkeeperPrintLogs(printAll: false)
            try checkEqual(logs.count, 1, tag: "Function: \(#function), line: \(#line)")
            var lastLog = logs[0]
            try checkEqual(lastLog.ins, SatocardINS.exportSecret.rawValue, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(lastLog.sid1, exportedHeader.sid, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(lastLog.sid2, 0xFFFF, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(lastLog.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
            
            // export entropy in plaintext
            let entropyHeader = headers[1]
            let entropyObject =  try cmdSet.seedkeeperExportSecret(sid: entropyHeader.sid, sidPubkey: nil)
            exportedHeader = entropyObject.secretHeader
            try checkEqual(exportedHeader.sid, entropyHeader.sid, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedHeader.type, entropyHeader.type, tag: "Function: \(#function), line: \(#line)") //SeedkeeperSecretType.masterseed)
            try checkEqual(exportedHeader.origin, entropyHeader.origin, tag: "Function: \(#function), line: \(#line)") //SeedkeeperSecretOrigin.generatedOnCard)
            try checkEqual(exportedHeader.exportRights, entropyHeader.exportRights, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedHeader.fingerprintBytes, entropyHeader.fingerprintBytes, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedHeader.rfu2, entropyHeader.rfu2, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedHeader.subtype, entropyHeader.subtype, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedHeader.label, entropyHeader.label, tag: "Function: \(#function), line: \(#line)")
            // test master password fingerprint
            try checkEqual(entropyObject.getFingerprintFromSecret(), entropyHeader.fingerprintBytes, tag: "Function: \(#function), line: \(#line)")
            
            // check last log
            (logs, nbTotalLogs, nbAvailLogs) = try cmdSet.seedkeeperPrintLogs(printAll: false)
            try checkEqual(logs.count, 1, tag: "Function: \(#function), line: \(#line)")
            lastLog = logs[0]
            try checkEqual(lastLog.ins, SatocardINS.exportSecret.rawValue, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(lastLog.sid1, exportedHeader.sid, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(lastLog.sid2, 0xFFFF, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(lastLog.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
            
            // check exported entropy includes entropy provided by user (the rest is generated by the chip)
            let entropyFromUser = Array(entropyObject.secretBytes[1...entropy.count]) // first byte is entropy-size
            try checkEqual(entropyFromUser, entropy, tag: "Function: \(#function), line: \(#line)")
            // test entropy derivation: Secret is the 'size' first bytes of sha512(entropy)
            let entropyRaw = Array(entropyObject.secretBytes[1..<entropyObject.secretBytes.count])
            let entropyHash = Array(entropyRaw.sha512()[0..<size])
            try checkEqual(entropyHash, Array(secretObject.secretBytes[1..<secretObject.secretBytes.count]), tag: "Function: \(#function), line: \(#line)")
            
            // derive secrets from master password: Derived_data is the 64bytes HmacSha512 of Salt (used as key) and Master_Password (used as message)
            // random salt
            let salt = try randomBytes(count: size)
            let (_, derivedSecretObject) = try cmdSet.seedkeeperDeriveMasterPassword(salt: salt,
                                                                                     sid: secretHeader.sid)
            let secretRaw = Array(secretObject.secretBytes[1..<secretObject.secretBytes.count])
            let swDerivation = try HMAC(key: salt, variant: .sha512).authenticate(secretRaw)
            let hwDerivation = derivedSecretObject.secret
            try checkEqual(swDerivation, hwDerivation, tag: "Function: \(#function), line: \(#line)")
            
            // erase secret and entropy if supported
            if cardStatus.protocolVersion >= 0x0002 {
                var rapdu = try cmdSet.seedkeeperResetSecret(sid: secretHeader.sid)
                try checkEqual(rapdu.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
                rapdu = try cmdSet.seedkeeperResetSecret(sid: entropyHeader.sid)
                try checkEqual(rapdu.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
            } else {
                log.info("Seedkeeper v\(cardStatus.protocolVersion): Erasing secret not supported!",
                            tag: "Function: \(#function), line: \(#line)")
            }
        }// for
        nbTestSuccess+=1
    }
    
    // MARK: testImportExportSecretPlain
    public func testImportExportSecretPlain() throws {
        
        let bip39_12 = try Mnemonic.generateMnemonic(strength: 128)
        let bip39_18 = try Mnemonic.generateMnemonic(strength: 192)
        let bip39_24 = try Mnemonic.generateMnemonic(strength: 256)
        let bip39s=[bip39_12, bip39_18, bip39_24]
        
        for index in 0..<bip39s.count {
            let bip39String = bip39s[index]
            //let masterSeed = Mnemonic.deterministicSeedBytes(from bip39String)
            let secretBytes = [UInt8(Array(bip39String.utf8).count)] + Array(bip39String.utf8)
            let secretFingerprintBytes = SeedkeeperSecretHeader.getFingerprintBytes(secretBytes: secretBytes)
            let label = "Test BIP39 size:\(12 + index*6)"
            let secretHeader = SeedkeeperSecretHeader(type: SeedkeeperSecretType.bip39Mnemonic,
                                                      subtype: UInt8(0x00),
                                                      fingerprintBytes: secretFingerprintBytes,
                                                      label: label)
            let secretObject = SeedkeeperSecretObject(secretBytes: secretBytes,
                                                      secretHeader: secretHeader,
                                                      isEncrypted: false)
            
            // import secret
            let (rapdu, sid, fingerprintBytes) = try cmdSet.seedkeeperImportSecret(secretObject: secretObject)
            try checkEqual(rapdu.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(fingerprintBytes, secretFingerprintBytes, tag: "Function: \(#function), line: \(#line)")
            
            // export secret
            let exportedSecretObject = try cmdSet.seedkeeperExportSecret(sid: sid)
            let exportedSecretHeader = exportedSecretObject.secretHeader
            try checkEqual(exportedSecretHeader.type, secretHeader.type, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedSecretHeader.subtype, secretHeader.subtype, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedSecretHeader.origin, secretHeader.origin, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedSecretHeader.exportRights, secretHeader.exportRights, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedSecretHeader.fingerprintBytes, secretHeader.fingerprintBytes, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedSecretHeader.rfu2, secretHeader.rfu2, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedSecretHeader.label, secretHeader.label, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedSecretObject.secretBytes, exportedSecretObject.secretBytes, tag: "Function: \(#function), line: \(#line)")

            // todo: test logging
            
            // erase secret if supported
            if cardStatus.protocolVersion >= 0x0002 {
                var rapdu = try cmdSet.seedkeeperResetSecret(sid: exportedSecretHeader.sid)
                try checkEqual(rapdu.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
            } else {
                log.info("Seedkeeper v\(cardStatus.protocolVersion): Erasing secret not supported!",
                            tag: "Function: \(#function), line: \(#line)")
            }
            
        }// for
        
    }
    
    // MARK: testImportExportSecretEncrypted
    public func testImportExportSecretEncrypted() throws {
        // get authentikey then import it in plaintext
        let (rapdu, authentikeyBytes, authentikeyHex) = try cmdSet.cardGetAuthentikey()
        let authentikeySecretBytes = [UInt8(authentikeyBytes.count)] + authentikeyBytes
        let authentikeyFingerprintBytes = SeedkeeperSecretHeader.getFingerprintBytes(secretBytes: authentikeySecretBytes)
        let authentikeyLabel = "Test Seedkeeper own kauthentikey"
        let authentikeySecretHeader = SeedkeeperSecretHeader(type: SeedkeeperSecretType.pubkey,
                                                  subtype: UInt8(0x00),
                                                  fingerprintBytes: authentikeyFingerprintBytes,
                                                  label: authentikeyLabel)
        let authentikeySecretObject = SeedkeeperSecretObject(secretBytes: authentikeySecretBytes,
                                                  secretHeader: authentikeySecretHeader,
                                                  isEncrypted: false)
        
        // import secret
        let (rapdu2, authentikeySid, fingerprintBytes) = try cmdSet.seedkeeperImportSecret(secretObject: authentikeySecretObject)
        try checkEqual(rapdu.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
        try checkEqual(fingerprintBytes, authentikeyFingerprintBytes, tag: "Function: \(#function), line: \(#line)")
        
        // export the authentikey
        let exportedAuthentikeySecretObject = try cmdSet.seedkeeperExportSecret(sid: authentikeySid)
        let exportedAuthentikeySecretHeader = exportedAuthentikeySecretObject.secretHeader
        try checkEqual(exportedAuthentikeySecretHeader.type, authentikeySecretHeader.type, tag: "Function: \(#function), line: \(#line)")
        try checkEqual(exportedAuthentikeySecretHeader.subtype, authentikeySecretHeader.subtype, tag: "Function: \(#function), line: \(#line)")
        try checkEqual(exportedAuthentikeySecretHeader.origin, authentikeySecretHeader.origin, tag: "Function: \(#function), line: \(#line)")
        try checkEqual(exportedAuthentikeySecretHeader.exportRights, authentikeySecretHeader.exportRights, tag: "Function: \(#function), line: \(#line)")
        try checkEqual(exportedAuthentikeySecretHeader.fingerprintBytes, authentikeySecretHeader.fingerprintBytes, tag: "Function: \(#function), line: \(#line)")
        try checkEqual(exportedAuthentikeySecretHeader.rfu2, authentikeySecretHeader.rfu2, tag: "Function: \(#function), line: \(#line)")
        try checkEqual(exportedAuthentikeySecretHeader.label, authentikeySecretHeader.label, tag: "Function: \(#function), line: \(#line)")
        try checkEqual(exportedAuthentikeySecretObject.secretBytes, authentikeySecretObject.secretBytes, tag: "Function: \(#function), line: \(#line)")

        // generate MasterSeed and export encrypted
        let seedSizes = [16, 32, 48, 64]
        for index in 0..<seedSizes.count {
            let size = seedSizes[index]
            
            // generate masterseed on card
            let masterseedExportRights = SeedkeeperExportRights.exportEncryptedOnly
            let masterseedLabel = "Test masterseed  \(size) bytes export-encrypted"
            let (rapdu3, masterseedHeader) = try cmdSet.seedkeeperGenerateMasterseed(seedSize: size, exportRights: masterseedExportRights, label: masterseedLabel)
            try checkEqual(rapdu3.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
            
            // check last log
            var (logs, nbTotalLogs, nbAvailLogs) = try cmdSet.seedkeeperPrintLogs(printAll: false)
            try checkEqual(logs.count, 1, tag: "Function: \(#function), line: \(#line)")
            var lastLog = logs[0]
            try checkEqual(lastLog.ins, SatocardINS.generateMasterseed.rawValue, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(lastLog.sid1, masterseedHeader.sid, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(lastLog.sid2, 0xFFFF, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(lastLog.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
            
            // export secret in plaintext => should fail given the export rights
            do {
                let exportedMasterseedObject = try cmdSet.seedkeeperExportSecret(sid: masterseedHeader.sid)
                // force fail if it does not throw
                try checkEqual(true, false, tag: "Function: \(#function), line: \(#line)")
            } catch let error {
                log.info("Failed to export masterseed in plaintex with error: \(error)", tag: "Function: \(#function), line: \(#line)")
            }
            
            // test logs for fail
            (logs, nbTotalLogs, nbAvailLogs) = try cmdSet.seedkeeperPrintLogs(printAll: false)
            try checkEqual(logs.count, 1, tag: "Function: \(#function), line: \(#line)")
            lastLog = logs[0]
            try checkEqual(lastLog.ins, SatocardINS.exportSecret.rawValue, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(lastLog.sid1, masterseedHeader.sid, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(lastLog.sid2, 0xFFFF, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(lastLog.sw, StatusWord.exportNotAllowed.rawValue, tag: "Function: \(#function), line: \(#line)")
            
            // export it encrypted
            let exportedMasterseedObject = try cmdSet.seedkeeperExportSecret(sid: masterseedHeader.sid, sidPubkey: authentikeySid)
            let exportedMasterseedHeader = exportedMasterseedObject.secretHeader
            try checkEqual(exportedMasterseedHeader.type, masterseedHeader.type, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedMasterseedHeader.subtype, masterseedHeader.subtype, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedMasterseedHeader.origin, masterseedHeader.origin, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedMasterseedHeader.exportRights, masterseedHeader.exportRights, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedMasterseedHeader.fingerprintBytes, masterseedHeader.fingerprintBytes, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedMasterseedHeader.rfu2, masterseedHeader.rfu2, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedMasterseedHeader.label, masterseedHeader.label, tag: "Function: \(#function), line: \(#line)")
            
            // check last log
            (logs, nbTotalLogs, nbAvailLogs) = try cmdSet.seedkeeperPrintLogs(printAll: false)
            try checkEqual(logs.count, 1, tag: "Function: \(#function), line: \(#line)")
            lastLog = logs[0]
            try checkEqual(lastLog.ins, SatocardINS.exportSecret.rawValue, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(lastLog.sid1, masterseedHeader.sid, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(lastLog.sid2, authentikeySid, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(lastLog.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
            
            // reimport it encrypted then check if fingerprints match
            let (rapdu4, masterseedSid, masterseedFingerprintBytes) = try cmdSet.seedkeeperImportSecret(secretObject: exportedMasterseedObject)
            try checkEqual(rapdu4.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(masterseedFingerprintBytes, masterseedHeader.fingerprintBytes, tag: "Function: \(#function), line: \(#line)")
            
            // check logs
            (logs, nbTotalLogs, nbAvailLogs) = try cmdSet.seedkeeperPrintLogs(printAll: false)
            try checkEqual(logs.count, 1, tag: "Function: \(#function), line: \(#line)")
            lastLog = logs[0]
            try checkEqual(lastLog.ins, SatocardINS.importSecret.rawValue, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(lastLog.sid1, masterseedSid, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(lastLog.sid2, authentikeySid, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(lastLog.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
            
            // erase secret if supported
            if cardStatus.protocolVersion >= 0x0002 {
                var rapdu = try cmdSet.seedkeeperResetSecret(sid: masterseedHeader.sid)
                try checkEqual(rapdu.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
                rapdu = try cmdSet.seedkeeperResetSecret(sid: masterseedSid)
                try checkEqual(rapdu.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
            } else {
                log.info("Seedkeeper v\(cardStatus.protocolVersion): Erasing secret not supported!",
                            tag: "Function: \(#function), line: \(#line)")
            }
        }// for
        
        // erase authentikey (if supported)
        if cardStatus.protocolVersion >= 0x0002 {
            var rapdu = try cmdSet.seedkeeperResetSecret(sid: authentikeySid)
            try checkEqual(rapdu.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
        } else {
            log.info("Seedkeeper v\(cardStatus.protocolVersion): Erasing secret not supported!",
                        tag: "Function: \(#function), line: \(#line)")
        }
        
    }
    
    // MARK: testBip39MnemonicV2
    public func testBip39MnemonicV2() throws {
        log.info("[CardState.testBip39MnemonicV2] Start", tag: "Function: \(#function), line: \(#line)")
        
        // introduced in Seedkeeper v0.2
        if cardStatus.protocolVersion < 0x0002 {
            log.info("Seedkeeper v\(cardStatus.protocolVersion): Masterseed with BIP39 not supported!",
                        tag: "Function: \(#function), line: \(#line)")
        }
        
//        let bip39_12 = try Mnemonic.generateMnemonic(strength: 128)
//        let bip39_18 = try Mnemonic.generateMnemonic(strength: 192)
//        let bip39_24 = try Mnemonic.generateMnemonic(strength: 256)
//        let bip39s = [bip39_12, bip39_18, bip39_24]
        let entropySizes = [16, 24, 32]
        let passphrases = ["", "", "HelloDarknessMyOldFriend"]
        
        for index in 0..<entropySizes.count {
            //let bip39String = bip39s[index]
            let entropySize = entropySizes[index]
            let randomEntropyBytes = try randomBytes(count: entropySize)
            let randomEntropyHex = randomEntropyBytes.toHexString()
            print("[DEBUG testBip39MnemonicV2] randomEntropyHex: \(randomEntropyHex)")
            
            let bip39String = try Mnemonic.mnemonicString(hexString: randomEntropyHex)
            print("[DEBUG testBip39MnemonicV2] bip39String: \(bip39String)")
            
            let entropyBytes = try Mnemonic.mnemonicToEntropy(bip39: bip39String)
            print("[DEBUG testBip39MnemonicV2] entropyHex: \(entropyBytes.toHexString())")
            try checkEqual(entropyBytes, randomEntropyBytes, tag: "Function: \(#function), line: \(#line)")
            
            let passphrase = passphrases[index]
            let passphraseByte = Array(passphrase.utf8)
            let masterseedBytes =  try Mnemonic.mnemonicToMasterseed(mnemonic: bip39String,
                                                                     passphrase: passphrase,
                                                                     mnemonicType: MnemonicType.bip39)
            var secretBytes = [UInt8(masterseedBytes.count)] + masterseedBytes
            secretBytes += [MnemonicLanguage.english.rawValue]
            secretBytes += [UInt8(entropyBytes.count)] + entropyBytes
            secretBytes += [UInt8(passphraseByte.count)] + passphraseByte
                                 
            let secretFingerprintBytes = SeedkeeperSecretHeader.getFingerprintBytes(secretBytes: secretBytes)
            let label = "Test BIP39 size:\(12 + index*6)"
            let secretHeader = SeedkeeperSecretHeader(type: SeedkeeperSecretType.masterseed,
                                                      subtype: SeedkeeperMasterseedSubtype.bip39Mnemonic.rawValue,
                                                      fingerprintBytes: secretFingerprintBytes,
                                                      label: label)
            let secretObject = SeedkeeperSecretObject(secretBytes: secretBytes,
                                                      secretHeader: secretHeader,
                                                      isEncrypted: false)
            
            // import secret
            let (rapdu, sid, fingerprintBytes) = try cmdSet.seedkeeperImportSecret(secretObject: secretObject)
            try checkEqual(rapdu.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(fingerprintBytes, secretFingerprintBytes, tag: "Function: \(#function), line: \(#line)")
            
            // todo: test logging
            
            // export secret
            let exportedSecretObject = try cmdSet.seedkeeperExportSecret(sid: sid)
            let exportedSecretHeader = exportedSecretObject.secretHeader
            try checkEqual(exportedSecretHeader.type, secretHeader.type, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedSecretHeader.subtype, secretHeader.subtype, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedSecretHeader.origin, secretHeader.origin, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedSecretHeader.exportRights, secretHeader.exportRights, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedSecretHeader.fingerprintBytes, secretHeader.fingerprintBytes, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedSecretHeader.rfu2, secretHeader.rfu2, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedSecretHeader.label, secretHeader.label, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedSecretObject.secretBytes, secretObject.secretBytes, tag: "Function: \(#function), line: \(#line)")
            
            // todo: test logging
            
            // erase secret if supported
            if cardStatus.protocolVersion >= 0x0002 {
                var rapdu = try cmdSet.seedkeeperResetSecret(sid: exportedSecretHeader.sid)
                try checkEqual(rapdu.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
            } else {
                log.info("Seedkeeper v\(cardStatus.protocolVersion): Erasing secret not supported!",
                            tag: "Function: \(#function), line: \(#line)")
            }
        }// for
        
    }
    
    
    // MARK: testCardBip32GetExtendedkeySeedVector1
    public func testCardBip32GetExtendedkeySeedVector1() throws {
        log.info("[CardState.testCardBip32GetExtendedkeySeedVector1] Start", tag: "Function: \(#function), line: \(#line)")
        // Bip32 test vectors 1 (https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki#Test_Vectors)
        
        // introduced in Seedkeeper v0.2
        if cardStatus.protocolVersion < 0x0002 {
            log.info("Seedkeeper v\(cardStatus.protocolVersion): BIP32 derivation not supported!",
                        tag: "Function: \(#function), line: \(#line)")
        }
        
        // create a secret
        let masterseedHex = "000102030405060708090a0b0c0d0e0f"
        let masterseedBytes = masterseedHex.hexToBytes
        let secretBytes = [UInt8(masterseedBytes.count)] + masterseedBytes
        
        let secretFingerprintBytes = SeedkeeperSecretHeader.getFingerprintBytes(secretBytes: secretBytes)
        let label = "Test Masterseed BIP32 vector1"
        
        let secretHeader = SeedkeeperSecretHeader(type: SeedkeeperSecretType.masterseed,
                                                  subtype: SeedkeeperMasterseedSubtype.defaultSubtype.rawValue,
                                                  fingerprintBytes: secretFingerprintBytes,
                                                  label: label)
        let secretObject = SeedkeeperSecretObject(secretBytes: secretBytes,
                                                  secretHeader: secretHeader,
                                                  isEncrypted: false)
        
        // import secret
        var (rapdu, sid, fingerprintBytes) = try cmdSet.seedkeeperImportSecret(secretObject: secretObject)
        try checkEqual(rapdu.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
        try checkEqual(fingerprintBytes, secretFingerprintBytes, tag: "Function: \(#function), line: \(#line)")
        
        let paths=[ "m",
                "m/0'",
                "m/0'/1",
                "m/0'/1/2'",
                "m/0'/1/2'/2",
                "m/0'/1/2'/2/1000000000"]
        let xpubs=[ "xpub661MyMwAqRbcFtXgS5sYJABqqG9YLmC4Q1Rdap9gSE8NqtwybGhePY2gZ29ESFjqJoCu1Rupje8YtGqsefD265TMg7usUDFdp6W1EGMcet8",
                    "xpub68Gmy5EdvgibQVfPdqkBBCHxA5htiqg55crXYuXoQRKfDBFA1WEjWgP6LHhwBZeNK1VTsfTFUHCdrfp1bgwQ9xv5ski8PX9rL2dZXvgGDnw",
                    "xpub6ASuArnXKPbfEwhqN6e3mwBcDTgzisQN1wXN9BJcM47sSikHjJf3UFHKkNAWbWMiGj7Wf5uMash7SyYq527Hqck2AxYysAA7xmALppuCkwQ",
                    "xpub6D4BDPcP2GT577Vvch3R8wDkScZWzQzMMUm3PWbmWvVJrZwQY4VUNgqFJPMM3No2dFDFGTsxxpG5uJh7n7epu4trkrX7x7DogT5Uv6fcLW5",
                    "xpub6FHa3pjLCk84BayeJxFW2SP4XRrFd1JYnxeLeU8EqN3vDfZmbqBqaGJAyiLjTAwm6ZLRQUMv1ZACTj37sR62cfN7fe5JnJ7dh8zL4fiyLHV",
                    "xpub6H1LXWLaKsWFhvm6RVpEL9P4KfRZSW7abD2ttkWP3SSQvnyA8FSVqNTEcYFgJS2UaFcxupHiYkro49S8yGasTvXEYBVPamhGW6cFJodrTHy"]

        let xprvs=[ "xprv9s21ZrQH143K3QTDL4LXw2F7HEK3wJUD2nW2nRk4stbPy6cq3jPPqjiChkVvvNKmPGJxWUtg6LnF5kejMRNNU3TGtRBeJgk33yuGBxrMPHi",
                    "xprv9uHRZZhk6KAJC1avXpDAp4MDc3sQKNxDiPvvkX8Br5ngLNv1TxvUxt4cV1rGL5hj6KCesnDYUhd7oWgT11eZG7XnxHrnYeSvkzY7d2bhkJ7",
                    "xprv9wTYmMFdV23N2TdNG573QoEsfRrWKQgWeibmLntzniatZvR9BmLnvSxqu53Kw1UmYPxLgboyZQaXwTCg8MSY3H2EU4pWcQDnRnrVA1xe8fs",
                    "xprv9z4pot5VBttmtdRTWfWQmoH1taj2axGVzFqSb8C9xaxKymcFzXBDptWmT7FwuEzG3ryjH4ktypQSAewRiNMjANTtpgP4mLTj34bhnZX7UiM",
                    "xprvA2JDeKCSNNZky6uBCviVfJSKyQ1mDYahRjijr5idH2WwLsEd4Hsb2Tyh8RfQMuPh7f7RtyzTtdrbdqqsunu5Mm3wDvUAKRHSC34sJ7in334",
                    "xprvA41z7zogVVwxVSgdKUHDy1SKmdb533PjDz7J6N6mV6uS3ze1ai8FHa8kmHScGpWmj4WggLyQjgPie1rFSruoUihUZREPSL39UNdE3BBDu76",
        ]
        
        // subtests
        // test xpub
        for i in 0..<paths.count {
            print("Xpub Derivation \(i)")
            let path = paths[i]
            let xpub = try cmdSet.cardBip32GetXpub(path: path, xtype: XPUB_HEADERS_MAINNET.standard.rawValue, sid: sid)
            try checkEqual(xpub, xpubs[i], tag: "Function: \(#function), line: \(#line)")
        }
        
        // test xprv
        for i in 0..<paths.count {
            print("Xprv Derivation \(i)")
            let path = paths[i]
//            if let xprvBytes = Base58.base58CheckDecode(xprvs[i]){
//                print("xprvBytes1: \(xprvBytes.bytesToHex)")
//            }
//            if let xprvBytes = Base58.base58Decode(xprvs[i]){
//                print("xprvBytes2: \(xprvBytes.bytesToHex)")
//            }
            let xprv = try cmdSet.cardBip32GetXprv(path: path, xtype: XPRV_HEADERS_MAINNET.standard.rawValue, sid: sid)
            try checkEqual(xprv, xprvs[i], tag: "Function: \(#function), line: \(#line)")
        }
        
        // delete seed
        rapdu = try cmdSet.seedkeeperResetSecret(sid: sid)
        try checkEqual(rapdu.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
    }
    
    // MARK: testCardBip32GetExtendedkeySeedVector2
    public func testCardBip32GetExtendedkeySeedVector2() throws {
        log.info("[CardState.testCardBip32GetExtendedkeySeedVector2] Start", tag: "Function: \(#function), line: \(#line)")
        // Bip32 test vectors 1 (https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki#Test_Vectors)
        
        // introduced in Seedkeeper v0.2
        if cardStatus.protocolVersion < 0x0002 {
            log.info("Seedkeeper v\(cardStatus.protocolVersion): BIP32 derivation not supported!",
                        tag: "Function: \(#function), line: \(#line)")
        }
        
        // create a secret
        let masterseedHex = "fffcf9f6f3f0edeae7e4e1dedbd8d5d2cfccc9c6c3c0bdbab7b4b1aeaba8a5a29f9c999693908d8a8784817e7b7875726f6c696663605d5a5754514e4b484542"
        let masterseedBytes = masterseedHex.hexToBytes
        let secretBytes = [UInt8(masterseedBytes.count)] + masterseedBytes
        
        let secretFingerprintBytes = SeedkeeperSecretHeader.getFingerprintBytes(secretBytes: secretBytes)
        let label = "Test Masterseed BIP32 vector2"
        
        let secretHeader = SeedkeeperSecretHeader(type: SeedkeeperSecretType.masterseed,
                                                  subtype: SeedkeeperMasterseedSubtype.defaultSubtype.rawValue,
                                                  fingerprintBytes: secretFingerprintBytes,
                                                  label: label)
        let secretObject = SeedkeeperSecretObject(secretBytes: secretBytes,
                                                  secretHeader: secretHeader,
                                                  isEncrypted: false)
        
        // import secret
        var (rapdu, sid, fingerprintBytes) = try cmdSet.seedkeeperImportSecret(secretObject: secretObject)
        try checkEqual(rapdu.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
        try checkEqual(fingerprintBytes, secretFingerprintBytes, tag: "Function: \(#function), line: \(#line)")
        
        let paths = ["m",
                     "m/0",
                     "m/0/2147483647'",
                     "m/0/2147483647'/1",
                     "m/0/2147483647'/1/2147483646'",
                     "m/0/2147483647'/1/2147483646'/2"]
        let xpubs = ["xpub661MyMwAqRbcFW31YEwpkMuc5THy2PSt5bDMsktWQcFF8syAmRUapSCGu8ED9W6oDMSgv6Zz8idoc4a6mr8BDzTJY47LJhkJ8UB7WEGuduB",
                     "xpub69H7F5d8KSRgmmdJg2KhpAK8SR3DjMwAdkxj3ZuxV27CprR9LgpeyGmXUbC6wb7ERfvrnKZjXoUmmDznezpbZb7ap6r1D3tgFxHmwMkQTPH",
                     "xpub6ASAVgeehLbnwdqV6UKMHVzgqAG8Gr6riv3Fxxpj8ksbH9ebxaEyBLZ85ySDhKiLDBrQSARLq1uNRts8RuJiHjaDMBU4Zn9h8LZNnBC5y4a",
                     "xpub6DF8uhdarytz3FWdA8TvFSvvAh8dP3283MY7p2V4SeE2wyWmG5mg5EwVvmdMVCQcoNJxGoWaU9DCWh89LojfZ537wTfunKau47EL2dhHKon",
                     "xpub6ERApfZwUNrhLCkDtcHTcxd75RbzS1ed54G1LkBUHQVHQKqhMkhgbmJbZRkrgZw4koxb5JaHWkY4ALHY2grBGRjaDMzQLcgJvLJuZZvRcEL",
                     "xpub6FnCn6nSzZAw5Tw7cgR9bi15UV96gLZhjDstkXXxvCLsUXBGXPdSnLFbdpq8p9HmGsApME5hQTZ3emM2rnY5agb9rXpVGyy3bdW6EEgAtqt"]
        let xprvs = ["xprv9s21ZrQH143K31xYSDQpPDxsXRTUcvj2iNHm5NUtrGiGG5e2DtALGdso3pGz6ssrdK4PFmM8NSpSBHNqPqm55Qn3LqFtT2emdEXVYsCzC2U",
                     "xprv9vHkqa6EV4sPZHYqZznhT2NPtPCjKuDKGY38FBWLvgaDx45zo9WQRUT3dKYnjwih2yJD9mkrocEZXo1ex8G81dwSM1fwqWpWkeS3v86pgKt",
                     "xprv9wSp6B7kry3Vj9m1zSnLvN3xH8RdsPP1Mh7fAaR7aRLcQMKTR2vidYEeEg2mUCTAwCd6vnxVrcjfy2kRgVsFawNzmjuHc2YmYRmagcEPdU9",
                     "xprv9zFnWC6h2cLgpmSA46vutJzBcfJ8yaJGg8cX1e5StJh45BBciYTRXSd25UEPVuesF9yog62tGAQtHjXajPPdbRCHuWS6T8XA2ECKADdw4Ef",
                     "xprvA1RpRA33e1JQ7ifknakTFpgNXPmW2YvmhqLQYMmrj4xJXXWYpDPS3xz7iAxn8L39njGVyuoseXzU6rcxFLJ8HFsTjSyQbLYnMpCqE2VbFWc",
                     "xprvA2nrNbFZABcdryreWet9Ea4LvTJcGsqrMzxHx98MMrotbir7yrKCEXw7nadnHM8Dq38EGfSh6dqA9QWTyefMLEcBYJUuekgW4BYPJcr9E7j",]
        
        // subtests
        // test xpub
        for i in 0..<paths.count {
            print("Xpub Derivation \(i)")
            let path = paths[i]
            let xpub = try cmdSet.cardBip32GetXpub(path: path, xtype: XPUB_HEADERS_MAINNET.standard.rawValue, sid: sid)
            try checkEqual(xpub, xpubs[i], tag: "Function: \(#function), line: \(#line)")
        }
        
        // test xprv
        for i in 0..<paths.count {
            print("Xprv Derivation \(i)")
            let path = paths[i]
//            if let xprvBytes = Base58.base58CheckDecode(xprvs[i]){
//                print("xprvBytes1: \(xprvBytes.bytesToHex)")
//            }
//            if let xprvBytes = Base58.base58Decode(xprvs[i]){
//                print("xprvBytes2: \(xprvBytes.bytesToHex)")
//            }
            let xprv = try cmdSet.cardBip32GetXprv(path: path, xtype: XPRV_HEADERS_MAINNET.standard.rawValue, sid: sid)
            try checkEqual(xprv, xprvs[i], tag: "Function: \(#function), line: \(#line)")
        }
        
        // delete seed
        rapdu = try cmdSet.seedkeeperResetSecret(sid: sid)
        try checkEqual(rapdu.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
    }
    
    // MARK: testCardBip32GetExtendedkeySeedVector3
    public func testCardBip32GetExtendedkeySeedVector3() throws {
        log.info("[CardState.testCardBip32GetExtendedkeySeedVector3] Start", tag: "Function: \(#function), line: \(#line)")
        // Bip32 test vectors 1 (https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki#Test_Vectors)
        
        // introduced in Seedkeeper v0.2
        if cardStatus.protocolVersion < 0x0002 {
            log.info("Seedkeeper v\(cardStatus.protocolVersion): BIP32 derivation not supported!",
                        tag: "Function: \(#function), line: \(#line)")
        }
        
        // create a secret
        let masterseedHex = "4b381541583be4423346c643850da4b320e46a87ae3d2a4e6da11eba819cd4acba45d239319ac14f863b8d5ab5a0d0c64d2e8a1e7d1457df2e5a3c51c73235be"
        let masterseedBytes = masterseedHex.hexToBytes
        let secretBytes = [UInt8(masterseedBytes.count)] + masterseedBytes
        
        let secretFingerprintBytes = SeedkeeperSecretHeader.getFingerprintBytes(secretBytes: secretBytes)
        let label = "Test Masterseed BIP32 vector3"
        
        let secretHeader = SeedkeeperSecretHeader(type: SeedkeeperSecretType.masterseed,
                                                  subtype: SeedkeeperMasterseedSubtype.defaultSubtype.rawValue,
                                                  fingerprintBytes: secretFingerprintBytes,
                                                  label: label)
        let secretObject = SeedkeeperSecretObject(secretBytes: secretBytes,
                                                  secretHeader: secretHeader,
                                                  isEncrypted: false)
        
        // import secret
        var (rapdu, sid, fingerprintBytes) = try cmdSet.seedkeeperImportSecret(secretObject: secretObject)
        try checkEqual(rapdu.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
        try checkEqual(fingerprintBytes, secretFingerprintBytes, tag: "Function: \(#function), line: \(#line)")
        
        let paths = [ "m",
                      "m/0'"]
        let xpubs = [ "xpub661MyMwAqRbcEZVB4dScxMAdx6d4nFc9nvyvH3v4gJL378CSRZiYmhRoP7mBy6gSPSCYk6SzXPTf3ND1cZAceL7SfJ1Z3GC8vBgp2epUt13",
                      "xpub68NZiKmJWnxxS6aaHmn81bvJeTESw724CRDs6HbuccFQN9Ku14VQrADWgqbhhTHBaohPX4CjNLf9fq9MYo6oDaPPLPxSb7gwQN3ih19Zm4Y"]
        let xprvs = [ "xprv9s21ZrQH143K25QhxbucbDDuQ4naNntJRi4KUfWT7xo4EKsHt2QJDu7KXp1A3u7Bi1j8ph3EGsZ9Xvz9dGuVrtHHs7pXeTzjuxBrCmmhgC6",
                      "xprv9uPDJpEQgRQfDcW7BkF7eTya6RPxXeJCqCJGHuCJ4GiRVLzkTXBAJMu2qaMWPrS7AANYqdq6vcBcBUdJCVVFceUvJFjaPdGZ2y9WACViL4L"]
        
        // subtests
        // test xpub
        for i in 0..<paths.count {
            print("Xpub Derivation \(i)")
            let path = paths[i]
            let xpub = try cmdSet.cardBip32GetXpub(path: path, xtype: XPUB_HEADERS_MAINNET.standard.rawValue, sid: sid)
            try checkEqual(xpub, xpubs[i], tag: "Function: \(#function), line: \(#line)")
        }
        
        // test xprv
        for i in 0..<paths.count {
            print("Xprv Derivation \(i)")
            let path = paths[i]
            let xprv = try cmdSet.cardBip32GetXprv(path: path, xtype: XPRV_HEADERS_MAINNET.standard.rawValue, sid: sid)
            try checkEqual(xprv, xprvs[i], tag: "Function: \(#function), line: \(#line)")
        }
        
        // delete seed
        rapdu = try cmdSet.seedkeeperResetSecret(sid: sid)
        try checkEqual(rapdu.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
    }

    // MARK: testCardBip32GetExtendedkeyBip85
    public func testCardBip32GetExtendedkeyBip85() throws {
        log.info("[CardState.testCardBip32GetExtendedkeyBip85] Start", tag: "Function: \(#function), line: \(#line)")
        
        // introduced in Seedkeeper v0.2
        if cardStatus.protocolVersion < 0x0002 {
            log.info("Seedkeeper v\(cardStatus.protocolVersion): BIP32 derivation not supported!",
                        tag: "Function: \(#function), line: \(#line)")
        }
        
        // vectors generated using https://iancoleman.io/bip39/#english
        let wordlist = "english"
        let bip39 = "panel rally element develop cloud diamond brother rack scale path burger arctic"
        let masterseed = "d42b84073d7b0a6ceae2b37eeeffa5f763678f1cbf17f22ed2f8a38401528c769744fb5020ce05bc4e1f33dfb0d1d716c528d18dcfa2ab08c7efcee8655148f2"
        let masterseedBytes = masterseed.hexToBytes
        let xprv = "xprv9s21ZrQH143K4MUxTrPj2uJL5rvsAWYEhR5RxsC6tKAVoCyWhrdhD6JEgPmEoJCCKKyNLTFiCwvbBsKjmiobg3WQQT64EFnJ6SEvMkRWydx"
        let bip39bip85 = "devote sheriff detail immense current online clown letter loop spread weasel filter"
        // path m/83696968'/39'/{language}'/{words}'/{index}'
        let path = "m/83696968'/39'/0'/12'/0'"
        
        let entropyBytes = try Mnemonic.mnemonicToEntropy(bip39: bip39)
        print("[testCardBip32GetExtendedkeyBip85] entropyHex: \(entropyBytes.toHexString())")
        let passphraseBytes = [UInt8]()
        
        var secretBytes = [UInt8(masterseedBytes.count)] + masterseedBytes
        secretBytes += [MnemonicLanguage.english.rawValue]
        secretBytes += [UInt8(entropyBytes.count)] + entropyBytes
        secretBytes += [UInt8(passphraseBytes.count)] + passphraseBytes
                             
        let secretFingerprintBytes = SeedkeeperSecretHeader.getFingerprintBytes(secretBytes: secretBytes)
        let label = "Test BIP39 for BIP85 size:\(12)"
        let secretHeader = SeedkeeperSecretHeader(type: SeedkeeperSecretType.masterseed,
                                                  subtype: SeedkeeperMasterseedSubtype.bip39Mnemonic.rawValue,
                                                  fingerprintBytes: secretFingerprintBytes,
                                                  label: label)
        let secretObject = SeedkeeperSecretObject(secretBytes: secretBytes,
                                                  secretHeader: secretHeader,
                                                  isEncrypted: false)
        
        // import secret
        var (rapdu, sid, fingerprintBytes) = try cmdSet.seedkeeperImportSecret(secretObject: secretObject)
        try checkEqual(rapdu.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
        try checkEqual(fingerprintBytes, secretFingerprintBytes, tag: "Function: \(#function), line: \(#line)")
        
        // export secret
        let exportedSecretObject = try cmdSet.seedkeeperExportSecret(sid: sid)
        let exportedSecretHeader = exportedSecretObject.secretHeader
        try checkEqual(exportedSecretHeader.type, secretHeader.type, tag: "Function: \(#function), line: \(#line)")
        try checkEqual(exportedSecretHeader.subtype, secretHeader.subtype, tag: "Function: \(#function), line: \(#line)")
        try checkEqual(exportedSecretHeader.origin, secretHeader.origin, tag: "Function: \(#function), line: \(#line)")
        try checkEqual(exportedSecretHeader.exportRights, secretHeader.exportRights, tag: "Function: \(#function), line: \(#line)")
        try checkEqual(exportedSecretHeader.fingerprintBytes, secretHeader.fingerprintBytes, tag: "Function: \(#function), line: \(#line)")
        try checkEqual(exportedSecretHeader.rfu2, secretHeader.rfu2, tag: "Function: \(#function), line: \(#line)")
        try checkEqual(exportedSecretHeader.label, secretHeader.label, tag: "Function: \(#function), line: \(#line)")
        try checkEqual(exportedSecretObject.secretBytes, secretObject.secretBytes, tag: "Function: \(#function), line: \(#line)")
        
        // test BIP85 derivation on card
        var (bip85EntropyBytes, emptyBytes) =  try cmdSet.cardBip32GetExtendedkey(path: path, sid: sid, optionFlags: UInt8(0x04))
        print("bip85EntropyBytes: \(bip85EntropyBytes.bytesToHex)")

        // get Bip39 from entropy
        bip85EntropyBytes = Array(bip85EntropyBytes[0..<16]) // 16 bytes of entropy for 12 words
        let bip39Frombip85 = try Mnemonic.entropyToMnemonic(entropy: bip85EntropyBytes)
        print("bip39Frombip85: \(bip39Frombip85)")
        try checkEqual(bip39Frombip85, bip39bip85, tag: "Function: \(#function), line: \(#line)")
        
        // delete masterseed
        rapdu = try cmdSet.seedkeeperResetSecret(sid: sid)
        try checkEqual(rapdu.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
    }
    
    // MARK: testSeedkeeperMemory
    public func testSeedkeeperMemory() throws {
        // WARNING: this test will fill all the card available memory
        log.info("[CardState.testSeedkeeperMemory] Start", tag: "Function: \(#function), line: \(#line)")
        
        // introduced in Seedkeeper v0.2
        if cardStatus.protocolVersion < 0x0002 {
            log.info("Seedkeeper v\(cardStatus.protocolVersion): delete secret not supported!!",
                        tag: "Function: \(#function), line: \(#line)")
        }
        
        var sids = [Int]()
        var secrets = [SeedkeeperSecretObject]()
        var fingerprints = [String]()
        
        var secretSize = 1
        while true {
            print("secretSize: \(secretSize)")
            let secretBytes = [UInt8((secretSize>>8)%256), UInt8(secretSize%256)] + (try randomBytes(count: secretSize))

            // make header
            let secretFingerprintBytes = SeedkeeperSecretHeader.getFingerprintBytes(secretBytes: secretBytes)
            let label = "Test Data with \(secretSize+2) bytes"
            let secretHeader = SeedkeeperSecretHeader(type: SeedkeeperSecretType.data,
                                                      subtype: SeedkeeperSecretSubtype.defaultSubtype.rawValue,
                                                      fingerprintBytes: secretFingerprintBytes,
                                                      label: label)
            let secretObject = SeedkeeperSecretObject(secretBytes: secretBytes,
                                                      secretHeader: secretHeader,
                                                      isEncrypted: false)
            
            // import secret
            do {
                let (rapdu, sid, fingerprintBytes) = try cmdSet.seedkeeperImportSecret(secretObject: secretObject)
                try checkEqual(rapdu.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
                try checkEqual(fingerprintBytes, secretFingerprintBytes, tag: "Function: \(#function), line: \(#line)")
                sids += [sid]
                secrets += [secretObject]
                fingerprints += [fingerprintBytes.bytesToHex]
            }
            catch let error {
                print("[CardState.testSeedkeeperMemory] error during secret import: \(error)")
                break
            }
            
            // status
            let (rapdu2, seedkeeperStatus) = try cmdSet.seedkeeperGetStatus()
            print("seedkeeperStatus: \(seedkeeperStatus.toString())")
            secretSize+=1
        }
        
        // erase secrets from memory
        for index in 0..<sids.count {
            print("delete object: \(index) out of \(sids.count)")
            let sid = sids[index]
            let secretObject = secrets[index]
            let secretHeader = secretObject.secretHeader
            
            // export secret
            let exportedSecretObject = try cmdSet.seedkeeperExportSecret(sid: sid)
            let exportedSecretHeader = exportedSecretObject.secretHeader
            try checkEqual(exportedSecretHeader.type, secretHeader.type, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedSecretHeader.subtype, secretHeader.subtype, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedSecretHeader.origin, secretHeader.origin, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedSecretHeader.exportRights, secretHeader.exportRights, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedSecretHeader.fingerprintBytes, secretHeader.fingerprintBytes, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedSecretHeader.rfu2, secretHeader.rfu2, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedSecretHeader.label, secretHeader.label, tag: "Function: \(#function), line: \(#line)")
            try checkEqual(exportedSecretObject.secretBytes, secretObject.secretBytes, tag: "Function: \(#function), line: \(#line)")
            
            // delete object
            let rapdu = try cmdSet.seedkeeperResetSecret(sid: sid)
            try checkEqual(rapdu.sw, StatusWord.ok.rawValue, tag: "Function: \(#function), line: \(#line)")
        }
        
        // final status
        let (rapdu2, seedkeeperStatus) = try cmdSet.seedkeeperGetStatus()
        print("Finish: seedkeeperStatus: \(seedkeeperStatus.toString())")
    }
    
    //todo: test_memory_big_secrets
    //todo: test_memory_passwords
    
    // MARK: SATOCHIP
    public func testSatochip() throws {
        let log = LoggerService.shared
        log.info("Start Satochip tests", tag: "CardState.testSatochip")

        let pinString = "qqqq"
        let pinBytes = Array("qqqq".utf8)
        // let wrongPinBytes = Array("0000".utf8)
        // var rapdu = APDUResponse(sw1: 0x00, sw2: 0x00, data: [])
        
        // applet version
        // let appletVersion = cardStatus.protocolVersion
        
        // check setup status
        // let setupDone = cardStatus.setupDone
        // if (!setupDone){
        //     do {
        //         rapdu = try cmdSet.cardSetup(pin_tries0: 5, pin0: pinBytes)
        //     } catch let error {
        //         log.warning("Error: \(error)", tag:"CardState.testSatochip")
        //     }
        // }
        
        // ensure secure channel before sensitive operations
        if cardStatus.needsSecureChannel && !cmdSet.isSecureChannelOpen {
            do {
                _ = try cmdSet.cardInitiateSecureChannel()
                log.info("Secure channel established", tag: "CardState.testSatochip")
            } catch let error {
                log.error("Failed to establish secure channel: \(error)", tag: "CardState.testSatochip")
            }
        }

        // // verify PIN
        // log.info("verify PIN", tag: "CardState.testSatochip")

        // do {
        //     try cmdSet.cardVerifyPIN(pin: pinBytes)
        // } catch let error {
        //     log.warning("Error: \(error)", tag:"CardState.testSatochip")
        // }


        // More tests to go here
        
        log.info("End Satochip tests", tag: "CardState.testSatochip")

    }
    
    // MARK: ON DISCONNECTION
    func onDisconnection(error: Error) {
    }
    
    
    
    @MainActor
    func executeQuery() async {
        print("in executeQuery START")
        //dispatchGroup.enter()
        self.scan()
//        dispatchGroup.notify(queue: DispatchQueue.global()){
//            //todo remove
//        }
    }
    
    
    // MARK: Utilities
    public func checkEqual<T: Equatable>(_ lhs: T, _ rhs: T, tag: String) throws {
        let log = LoggerService.shared
        if (lhs != rhs){
            let msg = "CheckEqual failed: got \(lhs) but expected \(rhs) in \(tag)"
            log.error(msg, tag: tag)
            throw SatocardError.testError("[\(tag)] \(msg)")
        }
        else {
            log.debug("CheckEqual ok for: \(lhs)", tag: tag)
        }
    }
                    
    public func randomString(count: Int) -> String {
      let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<>&!%=+/.:$@€#"
      return String((0..<count).map{ _ in letters.randomElement()! })
    }
                    
//    public func randomBytes(length: Int) -> [UInt8] {
//        return Array(randomString(length: length).utf8)
//    }
    
    func randomBytes(count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)

        // Fill bytes with secure random data
        let status = SecRandomCopyBytes(
            kSecRandomDefault,
            count,
            &bytes
        )

        // A status of errSecSuccess indicates success
        if status == errSecSuccess {
            return bytes
        }
        else {
            throw SatocardError.randomGeneratorError
        }
    }
    
    
}
