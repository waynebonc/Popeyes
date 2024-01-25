//
//  ViewController.swift
//  Popeyes
//
//  Created by Wayne Bonnici on 27/04/2022.
//

import Cocoa

class ViewController: NSViewController {
    
    @IBOutlet weak var enterDfuButton: NSButton!
    @IBOutlet weak var rebootButton: NSButton!
    @IBOutlet var outputTextView: NSTextView!
    
    typealias STReturn = (status: Int32, error: OSStatus, data: Data)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
        
        var sysinfo: utsname = utsname()
        let exitCode = uname(&sysinfo)
        guard exitCode == EXIT_SUCCESS else {
            exit(1)
        }
        let machine = withUnsafePointer(to: &sysinfo.machine) { 
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { ptr in
                String(validatingUTF8: ptr)
            }
        }
        guard let machine = machine else {
            exit(1)
        }
#if !DEBUG
        if machine != "arm64" {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = "You can’t open this application because it is not supported on this Mac."
                alert.addButton(withTitle: "Quit")
                if alert.runModal() == .alertFirstButtonReturn {
                    exit(1)
                }
            }
        }
#endif
    }
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    
    @IBAction func enterDfu(_ sender: Any) {
        
        doCmd(["dfu"], needle: "rebooting target into dfu mode... ok", success: "Device is now in DFU mode!", error: "Could not put device in DFU mode.")
    }
    
    @IBAction func reboot(_ sender: Any) {
        
        doCmd(["reboot"], needle: "rebooting target into normal mode... ok", success: "Device is now rebooting!", error: "Could not reboot device.")
    }
    
    private func doCmd(_ args: [String], needle: String, success: String, error: String) {
        
        guard let macvdmtool = Bundle.main.url(forResource: "macvdmtool", withExtension: nil) else {
            return
        }
        
        self.outputTextView.string = ""
        self.enterDfuButton.isEnabled = false
        self.rebootButton.isEnabled = false
        
        DispatchQueue.global(qos: .userInitiated).async {
            
            var result: STReturn = (status: 0, error: 0, data: Data())
            do {
                
                result = try self.doSTTask(macvdmtool.path, with: args, cwd: macvdmtool.deletingLastPathComponent().path)
                
                guard let output = String(data: result.data, encoding: .utf8) else {
                    DispatchQueue.main.async {
                        self.enterDfuButton.isEnabled = true
                        self.rebootButton.isEnabled = true
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    self.outputTextView.string = output
                    
                    let completionAlert = NSAlert()
                    if result.status == 0 && output.lowercased().contains(needle) {
                        completionAlert.alertStyle = .informational
                        completionAlert.messageText = "Success"
                        completionAlert.informativeText = success
                    } else {
                        completionAlert.alertStyle = .warning
                        completionAlert.messageText = "Failed"
                        completionAlert.informativeText = "\(error)\nError \(result.status)"
                    }
                    completionAlert.runModal()
                    self.enterDfuButton.isEnabled = true
                    self.rebootButton.isEnabled = true
                }
                
            } catch STError.NoInit, STError.AuthCancelled {
                
                DispatchQueue.main.async {
                    self.enterDfuButton.isEnabled = true
                    self.rebootButton.isEnabled = true
                }
                return
                
            } catch STError.InvalidAuth {
                
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.alertStyle = .critical
                    alert.messageText = "Critical Failure"
                    alert.informativeText = "Could not run tool with sufficient privileges.\nError \(result.error)"
                    alert.runModal()
                    self.enterDfuButton.isEnabled = true
                    self.rebootButton.isEnabled = true
                }
                return
                
            } catch {
                // just to silence error
                return
            }
        }
    }
    
    private func doSTTask(_ path: String, with arguments: [String], cwd: String) throws -> STReturn {
        
        guard let task = STPrivilegedTask.init(launchPath: path, arguments: arguments, currentDirectory: cwd) else {
            throw STError.NoInit
        }
        
        let err = task.launch()
        if err == errAuthorizationCanceled {
            throw STError.AuthCancelled
        }
        
        if err != errAuthorizationSuccess {
            throw STError.InvalidAuth
        }
        
        task.waitUntilExit()
        
        return (task.terminationStatus, err, task.outputFileHandle.availableData)
    }
}
