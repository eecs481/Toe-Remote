//
//  DeviceViewController.swift
//  toe-remote
//


import UIKit
import CoreBluetooth

class DeviceViewController: UIViewController, BLEDelegate, ButtonDelegate {
    var ble: BLE?
    var peripheral: CBPeripheral
    var buttonLayout: ButtonLayout?
    var readBuffer: NSMutableData
    var index: Int
    var numButtons: UInt8?
    var buttonView: UIView?
    var selectionViewController: SelectionViewController?
    var viewLoaded: Bool
    var paused: Bool
    var editButton: UIButton?
    var backButton: UIButton?
    var progress: UIActivityIndicatorView?
    
    var isEdit: Bool
    
    init(selectionViewController: SelectionViewController?, ble: BLE?, peripheral: CBPeripheral) {
        self.selectionViewController = selectionViewController
        self.ble = ble
        self.peripheral = peripheral
        self.buttonLayout = selectionViewController?.cachedLayouts[peripheral.identifier.UUIDString]
        self.readBuffer = NSMutableData()
        self.index = 0
        self.viewLoaded = false
        self.isEdit = false
        self.paused = false
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("Method not implemented")
    }
    
    override func viewDidLoad() {
        self.view.backgroundColor = UIColor.whiteColor()
        addTitleView(self.view)
        let titleHeight = self.view.bounds.height / 10.0
        self.buttonView = UIView(frame: CGRectMake(0, titleHeight, self.view.bounds.width, titleHeight * 9.0))
        view.addSubview(buttonView!)
        if progress == nil {
            progress = UIActivityIndicatorView(activityIndicatorStyle: .Gray)
            let width: CGFloat = 100
            progress!.frame = CGRectMake((self.buttonView!.bounds.width - width)/2, (self.buttonView!.bounds.height - width)/2, width, width)
            self.buttonView!.addSubview(progress!)
        }
        if buttonLayout != nil {
            buttonLayout!.addToView(buttonView!)
            buttonLayout!.setDelegate(self)
        } else {
            progress!.startAnimating()
        }
        viewLoaded = true
    }
    
    func saveLayout() {
        guard let buttonLayout = buttonLayout else { return }
        let key = peripheral.identifier.UUIDString
        selectionViewController?.cachedLayouts.updateValue(buttonLayout, forKey: key)
    }
    
    func back() {
        if isEdit {
            stopEditing(false)
        } else {
            popView()
        }
    }
    
    func popView() {
        buttonLayout?.setDelegate(nil)
        self.dismissViewControllerAnimated(true, completion: {();
            guard let selectionViewController = self.selectionViewController else { return }
            self.ble?.delegate = selectionViewController
            self.ble?.disconnectFromPeripheral(self.peripheral)
            selectionViewController.deviceViewController = nil
            selectionViewController.retrieveNearbyDevices()
        })
    }
    
    func didButtonPress(button: Button) {
        if !isEdit {
            let bytes: [UInt8] = [0x01, button.id]
            ble?.write(data: NSData(bytes: bytes, length: 2))
        }
    }
    
    func stopEditing(save: Bool) {
        guard isEdit else { return }
        print("[DEBUG] Editing Stopped")
        isEdit = false
        editButton?.setTitle("Edit", forState: .Normal)
        backButton?.setTitle("Back", forState: .Normal)
        if save {
            if let buttonView = buttonView {
                buttonLayout?.makeThumbnail(buttonView)
            }
            saveLayout()
            buttonLayout?.save()
        } else {
            buttonLayout?.cancel()
        }
    }
    
    func startEditing() {
        guard !isEdit else { return }
        print("[DEBUG] Editing Started")
        isEdit = true
        editButton?.setTitle("Done", forState: .Normal)
        backButton?.setTitle("Cancel", forState: .Normal)
        
        buttonLayout?.edit()
    }
    
    func editButtonPressed() {
        if !isEdit {
            startEditing()
        } else {
            stopEditing(true)
        }
    }
    
    func addTitleView(view: UIView) {
        let titleBar = UIView(frame: CGRectMake(0, 0, view.bounds.width, view.bounds.height / 10))
        let backButtonWidth: CGFloat = 100.0
        
        let title = UILabel(frame: CGRectMake(backButtonWidth, 0, titleBar.bounds.width - 2*backButtonWidth, titleBar.bounds.size.height))
        title.text = ble?.getName(peripheral)
        if title.text == nil {
            title.text = peripheral.name
        }
        title.textAlignment = .Center
        titleBar.addSubview(title)
        
        backButton = UIButton(frame: CGRectMake(0, 0, backButtonWidth, titleBar.bounds.size.height))
        backButton!.setTitle("Back", forState: .Normal)
        backButton!.setTitleColor(UIColor.blueColor(), forState: .Normal)
        if selectionViewController != nil {
            backButton!.addTarget(self, action: #selector(DeviceViewController.back), forControlEvents: .TouchUpInside)
        }
        titleBar.addSubview(backButton!)
        
        editButton = UIButton(frame: CGRectMake(titleBar.bounds.width - backButtonWidth, 0, backButtonWidth, titleBar.bounds.size.height))
        editButton!.setTitle("Edit", forState: .Normal)
        editButton!.setTitleColor(UIColor.blueColor(), forState: .Normal)
        if selectionViewController != nil {
            editButton!.addTarget(self, action: #selector(editButtonPressed), forControlEvents: .TouchUpInside)
        }
        titleBar.addSubview(editButton!)
        
        view.addSubview(titleBar)
    }
    
    func bleDidScanTimeout() { }
    
    func bleDidUpdateState(state: CBCentralManagerState) {
        if state == .PoweredOn {
            if !paused {
                ble?.connectToPeripheral(peripheral)
            }
        }
    }
    
    func bleDidConnectToPeripheral() {
        print("[DEBUG] Connected to peripheral")
        if buttonLayout == nil {
            ble?.enableNotifications(true)
            print("[DEBUG] Sending Button Layout Request")
            let bytes: [UInt8] = [0x00, 0x00]
            ble?.write(data: NSData(bytes: bytes, length: 2))
        }
    }
    
    func bleDidDisconenctFromPeripheral() {
        print("[DEBUG] Disconnected from peripheral")
        if !paused {
            ble?.connectToPeripheral(peripheral)
        }
    }
    
    func bleDidReceiveData(data: NSData?) {
        if (buttonLayout == nil) {
            buttonLayout = ButtonLayout()
        }
        guard let data = data else { return }
        readBuffer.appendData(data)
        guard readBuffer.length - index > 0 else { return }
        if numButtons == nil {
            numButtons = UnsafePointer<UInt8>(readBuffer.bytes).memory
            index = index + 1
        }
        while numButtons > 0 && readBuffer.length - index >= Button.length {
            let range = NSRange(location: index, length: Button.length)
            let active = selectionViewController != nil
            buttonLayout!.addButton(self, data: readBuffer.subdataWithRange(range), active: active)
            index += Button.length
            numButtons = numButtons! - 1
        }
        if numButtons == 0 {
            print("[DEBUG] Recieved the layout")
            // ble.enableNotifications(false)
            saveLayout()
            if self.viewLoaded {
                progress!.stopAnimating()
                buttonLayout!.addToView(buttonView!)
            }
        }
    }
    
    func resume() {
        paused = false
        ble?.connectToPeripheral(peripheral)
    }
    
    func pause() {
        paused = true
    }
    
}