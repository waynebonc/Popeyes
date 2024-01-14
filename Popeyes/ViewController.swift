//
//  ViewController.swift
//  Popeyes
//
//  Created by Wayne Bonnici on 27/04/2022.
//

import Cocoa

class ViewController: NSViewController {
    
    @IBOutlet weak var enterDfuButton: NSButton!
    @IBOutlet var outputTextView: NSTextView!
    
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
    }
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    
    override func viewWillDisappear() {
        exit(0)
    }
    
    @IBAction func enterDfu(_ sender: Any) {
        
        guard let macvdmtool = Bundle.main.url(forResource: "macvdmtool", withExtension: nil) else {
            return
        }
        
        self.outputTextView.string = ""
        self.enterDfuButton.isEnabled = false
        
        DispatchQueue.global(qos: .userInitiated).async {
            
            guard let task = STPrivilegedTask.init(launchPath: macvdmtool.path, arguments: ["dfu"], currentDirectory: macvdmtool.deletingLastPathComponent().path) else {
                DispatchQueue.main.async {
                    self.enterDfuButton.isEnabled = true
                }
                return
            }
            
            let err = task.launch()
            if err == errAuthorizationCanceled {
                DispatchQueue.main.async {
                    self.enterDfuButton.isEnabled = true
                }
                return
            }
            
            if err != errAuthorizationSuccess {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.alertStyle = .critical
                    alert.messageText = "Critical Failure"
                    alert.informativeText = "Could not run DFU tool with sufficient privileges.\nError \(err)"
                    alert.runModal()
                    self.enterDfuButton.isEnabled = true
                }
                return
            }
            
            task.waitUntilExit()
            
            guard let output = String(data: task.outputFileHandle.availableData, encoding: .utf8) else {
                DispatchQueue.main.async {
                    self.enterDfuButton.isEnabled = true
                }
                return
            }
            
            DispatchQueue.main.async {
                self.outputTextView.string = output
                
                let completionAlert = NSAlert()
                if task.terminationStatus == 0 && output.lowercased().contains("rebooting target into dfu mode... ok") {
                    completionAlert.alertStyle = .informational
                    completionAlert.messageText = "Success"
                    completionAlert.informativeText = "Device is now in DFU mode!"
                } else {
                    completionAlert.alertStyle = .warning
                    completionAlert.messageText = "Failed"
                    completionAlert.informativeText = "Could not put device in DFU mode.\nError \(task.terminationStatus)"
                }
                completionAlert.runModal()
                self.enterDfuButton.isEnabled = true
            }
        }
    }
}

