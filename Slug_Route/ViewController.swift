//
//  ViewController.swift
//  Slug_Route
//
//  Created by Jeff on 11/5/16.
//  Copyright © 2016 Jeff. All rights reserved.
//

import UIKit
import MapKit
import CoreLocation
import FontAwesome_swift
import NotificationBannerSwift
import SystemConfiguration

class ViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, SWRevealViewControllerDelegate, MKMapViewDelegate, CLLocationManagerDelegate {
    
    @IBOutlet weak var popUpTableView: UITableView!
    @IBOutlet var popUpView: UIView!
    
    @IBAction func popUpViewButton(_ sender: UIButton) {
        UIView.animate(withDuration: 0.25, animations: {
            self.popUpView.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
            self.popUpView.alpha = 0
        }) { (success: Bool) in
            self.visualEffectView.removeFromSuperview()
            self.popUpView.removeFromSuperview()
        }
    }
    @IBOutlet weak var mapView: MKMapView!
    
    var busList = [Bus]()
    var busMarkerList = [BusMarker]()
    var visualEffectView: UIView!
    var numBusLabel: UILabel!
    var timeLabel: UILabel!
    var networkDisconnect = false
    let locationManager = CLLocationManager()
    var runTime = 0
    var waitTime = 8
    var slowConnection = true
    var noSlugRouteConnection = false
    
    let noInternetBanner = NotificationBanner(title: "No Internet Connection", subtitle: "Please Check Your Internet Connection", style: .danger)
    
    let noSlugRouteBanner = NotificationBanner(title: "Slug Route Is Under Maintenance", subtitle: "We apologize for the inconvenience", style: .danger)
    
    let slowConnectionBanner = NotificationBanner(title: "Connecting...", subtitle: "You may have a slow internet connection", style: .warning)
    
    // Map Key Names
    let mapName = [BusType.loop.rawValue,BusType.upperCampus.rawValue,BusType.outOfService.rawValue, BusType.nightOwl.rawValue, BusType.special.rawValue, BusStopType.innerStop.rawValue,BusStopType.outerStop.rawValue]
    
    //Map Key Images
    let mapImage = [UIImage(busImage: .loop), UIImage(busImage: .uppercampus), UIImage(busImage: .outofservice), UIImage(busImage: .nightowl), UIImage(busImage: .special),UIImage(busStopImage: .orange_stop), UIImage(busStopImage: .blue_stop)]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.naviToUCSC()
        mapView.delegate = self
        
        //Get user current location
        self.locationManager.requestWhenInUseAuthorization()
        
        if CLLocationManager.locationServicesEnabled() {
            self.locationManager.delegate = self
            self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
            self.locationManager.startUpdatingLocation()
        }
        
        //Navigation Bar Title
        let titleString = NSMutableAttributedString(string: "Slug Route", attributes: [NSFontAttributeName: UIFont(name: "Helvetica", size: 25.0)!])
        
        titleString.addAttribute(NSForegroundColorAttributeName, value: UIColor(red: 1.00, green: 0.63, blue: 0.00, alpha: 1.0), range: .init(location: 0, length: 4))
        
        titleString.addAttribute(NSForegroundColorAttributeName, value: UIColor(red: 0.08, green: 0.4, blue: 0.75, alpha: 1.0), range: .init(location: 5, length: 5))
        
        let titleLabel = UILabel()
        titleLabel.attributedText = titleString
        titleLabel.sizeToFit()
        
        self.navigationItem.titleView = titleLabel
        
        //Map Key Button
        let infoButton = UIButton(frame: CGRect(x: self.view.frame.size.width-60, y: 80, width: 50, height: 50))
        
        infoButton.layer.cornerRadius = 0.5 * infoButton.bounds.size.width
        infoButton.layer.shadowColor = UIColor.lightGray.cgColor
        infoButton.layer.shadowOffset = CGSize(width: 0.5,height: 1.5)
        infoButton.layer.shadowOpacity = 1.0;
        infoButton.layer.shadowRadius = 0.0;
        
        infoButton.backgroundColor = UIColor.white
        infoButton.setTitle("i", for: .normal)
        infoButton.setTitleColor(self.view.tintColor, for: .normal)
        
        infoButton.addTarget(self, action: #selector(infoButtonAction), for: UIControlEvents.touchUpInside)
        
        self.view.addSubview(infoButton)
        
        //Number of Service Label
        numBusLabel = InsetLabel(top:0, bottom: 0, left: 10, right: 10, rect: CGRect(x: 0, y: view.frame.height-45, width: self.view.frame.width/2, height: 45))
        
        numBusLabel.backgroundColor = UIColor(red: 0.08, green: 0.40, blue: 0.75, alpha: 1.0)
        numBusLabel.adjustsFontSizeToFitWidth = true
        numBusLabel.textAlignment = .left
        
        self.view.addSubview(numBusLabel)
        
        //Time Label
        timeLabel = InsetLabel(top: 0, bottom:0, left: 0, right: 10, rect: CGRect(x: self.view.frame.width/2, y: numBusLabel.frame.origin.y, width: self.view.frame.width/2, height: numBusLabel.frame.height) )
        
        timeLabel.backgroundColor = UIColor(red: 0.08, green: 0.40, blue: 0.75, alpha: 1.0)
        timeLabel.adjustsFontSizeToFitWidth = true
        timeLabel.textAlignment = .right
        
        self.view.addSubview(timeLabel)
        
        // Map Key Popup View
        self.popUpView.layer.cornerRadius = 15
        self.popUpView.clipsToBounds = true
        
        visualEffectView = UIView()
        visualEffectView.frame = self.view.bounds
        visualEffectView.backgroundColor = UIColor.gray.withAlphaComponent(0.6)
        
        //Slide Out/ Hamburger menu Setup
        addSlideMenuButton()
        
        //Adding navigation to origin button
        addHomeButton()
        
        self.revealViewController().delegate = self
        self.revealViewController().tapGestureRecognizer()
        self.revealViewController().panGestureRecognizer()
        
        //Auto fetch data from http server
        Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(self.fetchBusHttp), userInfo: nil, repeats: true)
        
        self.drawBusStops()
        
        //College Annotations
        self.drawCollegeMarkers()
        
    }
    
    @objc private func fetchBusHttp() {
        waitTime += 1
        
        if waitTime >= 20 {
            self.slowConnection = true
            waitTime = 0
        }
        
        if runTime == 0 {
            let url = URL(string: "http://bts.ucsc.edu:8081/location/get")
            
            let task = URLSession.shared.dataTask(with: url!) {
                (data, response, error) in
                
                self.slowConnection = false
                
                if error != nil {
                    self.busList.removeAll()
                    if error?._code == NSURLErrorTimedOut {
                        if self.networkDisconnect {
                            DispatchQueue.main.async {
                                self.noInternetBanner.dismiss()
                            }
                            self.networkDisconnect = false
                        }
                        
                        if self.noSlugRouteConnection == false {
                            DispatchQueue.main.async {
                                self.noSlugRouteBanner.show(bannerPosition: .bottom, on: self)
                            }
                            self.noSlugRouteBanner.autoDismiss = false
                            
                            self.noSlugRouteConnection = true
                        }
                        
                    } else {
                        if self.noSlugRouteConnection {
                            DispatchQueue.main.async {
                                self.noSlugRouteBanner.dismiss()
                            }
                            self.noSlugRouteConnection = false
                        }
                        
                        if self.networkDisconnect == false {
                            /*
                             let offlineString = NSMutableAttributedString(string: "No Internet Connection", attributes: [NSFontAttributeName: UIFont(name: "Helvetica", size: 25.0)!])
                             
                             offlineString.addAttribute(NSForegroundColorAttributeName, value: UIColor(red: 0.96, green: 0.26, blue: 0.21, alpha: 1.0), range: .init(location: 0, length: offlineString.length))
                             
                             DispatchQueue.main.async {
                             self.numBusLabel.attributedText = offlineString
                             self.timeLabel.textColor = UIColor(red: 0.96, green: 0.26, blue: 0.21, alpha: 1.0)
                             }
                             */
                            
                            DispatchQueue.main.async {
                                self.noInternetBanner.show(bannerPosition: .bottom, on: self)
                            }
                            self.noInternetBanner.autoDismiss = false
                            
                            self.networkDisconnect = true
                        }
                    }
                    
                    return
                }
                
                do {
                    self.runTime += 1
                    self.showCurrentTime(async: true)
                    
                    let jsonArray = try JSONSerialization.jsonObject(with: data!, options:
                        JSONSerialization.ReadingOptions.mutableContainers) as! [[String: AnyObject]]
                    
                    self.setBusList(resultArray: jsonArray)
                    
                    if self.networkDisconnect {
                        DispatchQueue.main.async {
                            self.noInternetBanner.dismiss()
                        }
                        self.networkDisconnect = false
                    }
                    
                    if self.noSlugRouteConnection {
                        DispatchQueue.main.async {
                            self.noSlugRouteBanner.dismiss()
                        }
                        self.noSlugRouteConnection = false
                    }
                    
                } catch let jsonError {
                    print("jsonError")
                    print(jsonError)
                }
                
            }
            
            if self.slowConnection && waitTime >= 12 {
                if isConnectedToNetwork() {
                    if self.networkDisconnect {
                        DispatchQueue.main.async {
                            self.noInternetBanner.dismiss()
                        }
                        self.networkDisconnect = false
                    }
                }
                
                if NotificationBannerQueue.default.numberOfBanners < 1 {
                    DispatchQueue.main.async {
                        self.slowConnectionBanner.show(bannerPosition: .bottom, on: self)
                    }
                }
                
            }
            
            task.resume()
        } else {
            self.runTime += 1
            if runTime >= 3 {
                self.runTime = 0
            }
            
            self.showCurrentTime(async: false)
        }
        
    }
    
    //Center Map to UCSC
    func naviToUCSC() {
        // Create a coordinate region that tells the map to display the Santa Cruz area
        let coordinateRegion = MKCoordinateRegionMakeWithDistance(CLLocation(latitude: 36.988550, longitude: -122.0586165).coordinate, 2500, 2500)
        
        mapView.setRegion(coordinateRegion, animated: true)
    }
    
    private func drawBusStops() {
        for mBusStop in BusStops().innerLoopList {
            let mapMarker = MapMarker(coordinate: mBusStop.location.coordinate, title: mBusStop.name, subtitle: BusStopType.innerStop.rawValue, image: UIImage(busStopImage: .orange_stop), zOrder: CGFloat(0))
            
            mapView.addAnnotation(mapMarker)
        }
        
        for mBusStop in BusStops().outerLoopList {
            let mapMarker = MapMarker(coordinate: mBusStop.location.coordinate, title: mBusStop.name, subtitle: BusStopType.outerStop.rawValue, image: UIImage(busStopImage: .blue_stop), zOrder: CGFloat(0))
            
            mapView.addAnnotation(mapMarker)
        }
    }
    
    private func addMapAnnotation(coordinate: CLLocationCoordinate2D, title: String, subtitle: String, id: Int) {
        let mapLabel = MapLabel(coordinate: coordinate, title: title, subtitle: subtitle, id: id)
        mapView.addAnnotation(mapLabel)
    }
    
    private func drawCollegeMarkers() {
        addMapAnnotation(coordinate: CLLocationCoordinate2D(latitude: 37.001095, longitude: -122.058221), title: "College 9 & 10", subtitle: "College Nine & Ten", id: 0)
        
        addMapAnnotation(coordinate: CLLocationCoordinate2D(latitude: 37.000470, longitude: -122.053966), title: "Crown & Merrill", subtitle: "Crown and Merrill College", id: 1)
        
        addMapAnnotation(coordinate: CLLocationCoordinate2D(latitude: 36.997086, longitude: -122.052971), title: "Cowell & Stevenson", subtitle: "Cowell and Stevenson", id: 2)
        
        addMapAnnotation(coordinate: CLLocationCoordinate2D(latitude: 36.994031, longitude: -122.053161), title: "East Field (OPERS)", subtitle: "East Field & OPERS Wellness Center", id: 3)
        
        addMapAnnotation(coordinate: CLLocationCoordinate2D(latitude: 36.986940, longitude: -122.055183), title: "The Village", subtitle: "The Village", id: 0)
        
        addMapAnnotation(coordinate: CLLocationCoordinate2D(latitude: 36.989283, longitude: -122.065581), title: "Oakes College", subtitle: "Oakes College", id: 0)
        
        addMapAnnotation(coordinate: CLLocationCoordinate2D(latitude: 36.991557, longitude: -122.064452), title: "Rachel Carson College", subtitle: "Rachel Carson College", id: 6)
        
        addMapAnnotation(coordinate: CLLocationCoordinate2D(latitude: 36.994184, longitude: -122.065362), title: "Porter College", subtitle: "Porter College", id: 0)
        
        addMapAnnotation(coordinate: CLLocationCoordinate2D(latitude: 36.997408, longitude: -122.066743), title: "Kresge College", subtitle: "Kresge College", id: 0)
        
        addMapAnnotation(coordinate: CLLocationCoordinate2D(latitude: 37.000826, longitude: -122.062422), title: "Jack Baskin", subtitle: "Jack Baskin & Engineering 2", id: 9)
        
        addMapAnnotation(coordinate: CLLocationCoordinate2D(latitude: 36.998862, longitude: -122.060872), title: "S&E Library", subtitle: "Science and Engineering Library", id: 9)
        
        addMapAnnotation(coordinate: CLLocationCoordinate2D(latitude: 36.995584, longitude: -122.058334), title: "McHenry Library", subtitle: "McHenry Library", id: 10)
        
        addMapAnnotation(coordinate: CLLocationCoordinate2D(latitude: 36.998035, longitude: -122.056053), title: "Quarry Plaza", subtitle: "Quarry Plaza", id: 9)
        
        addMapAnnotation(coordinate: CLLocationCoordinate2D(latitude: 36.991948, longitude: -122.067853), title: "Family Student Housing", subtitle: "Family Student Housing", id: 11)
        
        addMapAnnotation(coordinate: CLLocationCoordinate2D(latitude: 36.994941, longitude: -122.062052), title: "Media Theater", subtitle: "Media Theater", id: 9)
        
        addMapAnnotation(coordinate: CLLocationCoordinate2D(latitude: 36.993298, longitude: -122.060217), title: "Music Center", subtitle: "Music Center", id: 9)
        
        addMapAnnotation(coordinate: CLLocationCoordinate2D(latitude: 36.999381, longitude: -122.057484), title: "Health Center", subtitle: "Health Center", id: 9)
    }
    
    private func setBusList(resultArray: [[String: AnyObject]]) {
        if busList.count != resultArray.count || resultArray.count == 0 {
            self.showNumBus(numBus: resultArray.count)
        }
        
        busList.removeAll()
        
        for jsonObject in resultArray {
            busList.append(Bus(id: Int(jsonObject["id"] as! String)!, lat: jsonObject["lat"] as! Double, lon: jsonObject["lon"] as! Double, type: jsonObject["type"] as! String))
        }
        
        self.updateBusMarkers()
    }
    
    private func updateBusMarkers() {
        if busList.count == 0 {
            for m in busMarkerList {
                DispatchQueue.main.async {
                    self.mapView.removeAnnotation(m.marker)
                }
            }
            busMarkerList.removeAll()
            
        }
        
        for b in busList {
            
            var mBusMarker: BusMarker?
            
            for m in busMarkerList {
                if m.id == b.id {
                    mBusMarker = m
                    
                    if m.type != b.type {
                        let mIndex = busMarkerList.index(where: { $0 === m })
                        busMarkerList.remove(at: mIndex!)
                        DispatchQueue.main.async {
                            self.mapView.removeAnnotation(m.marker)
                        }
                        mBusMarker = nil
                    }
                    
                    break
                }
            }
            
            if let mBusMarker = mBusMarker {
                // if coordinates are different, update it
                if mBusMarker.marker.coordinate.latitude != b.location.coordinate.latitude ||
                    mBusMarker.marker.coordinate.longitude != b.location.coordinate.longitude {
                    DispatchQueue.main.async {
                        UIView.animate(withDuration: 0.25) {
                            mBusMarker.marker.coordinate = b.location.coordinate
                        }
                    }
                    
                }
            } else {
                var busImage: UIImage?
                
                switch( b.type.uppercased() ) {
                case "LOOP": busImage = UIImage(busImage: .loop)
                case "UPPER CAMPUS": busImage = UIImage(busImage: .uppercampus)
                case "NIGHT OWL": busImage = UIImage(busImage: .nightowl)
                case "LOOP OUT OF SERVICE AT BARN THEATER", "OUT OF SERVICE/SORRY": busImage = UIImage(busImage: .outofservice)
                default: busImage = UIImage(busImage: .special)
                }
                 
                DispatchQueue.main.async {
                    let mapMarker = MapMarker(coordinate: b.location.coordinate, title: b.type, subtitle: "", image:busImage!, zOrder: CGFloat(1))
                    self.mapView.addAnnotation(mapMarker)
                    
                    self.busMarkerList.append(BusMarker(id: b.id, marker: mapMarker, location: b.location, type: b.type))
                }
                
            }
            
        }
        
        //Remove off-line bus markers
        
        for (i, m) in busMarkerList.enumerated().reversed() {
            var removeCurrentMarker = true
            
            for b in busList {
                if ( b.id == m.id ) {
                    removeCurrentMarker = false
                    break
                }
            }
            
            if removeCurrentMarker {
                DispatchQueue.main.async {
                    self.mapView.removeAnnotation(m.marker)
                }
                busMarkerList.remove(at: i)
            }
        }
        
    }
    
    private func showNumBus(numBus: Int) {
        let numBusString = NSMutableAttributedString(string: "\(numBus)", attributes: [NSFontAttributeName: UIFont(name: "Helvetica", size: 25.0)!])
        
        var stringShuttle = "Shuttles"
        
        if numBus <= 1 {
            stringShuttle = "Shuttle"
        }
        
        numBusString.append(NSMutableAttributedString(string: " \(stringShuttle) in Service", attributes: [NSFontAttributeName: UIFont(name: "Helvetica", size: 12.0)!]))
        
        numBusString.addAttributes([NSForegroundColorAttributeName: UIColor.green], range: .init(location: 0, length: 2))
        
        DispatchQueue.main.async {
            self.numBusLabel.attributedText = numBusString
        }
    }
    
    private func showCurrentTime(async: Bool) {
        //Current Time Label Setup
        let dateFormatter = DateFormatter()
        
        dateFormatter.dateFormat = "h: mm a"
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .medium
        dateFormatter.timeZone = TimeZone(identifier: "PST")
        
        let currentTime = dateFormatter.string(from: Date())
        
        let currentTimeString = NSMutableAttributedString(string: "\(currentTime)", attributes: [NSFontAttributeName: UIFont(name: "Helvetica", size: 25.0)!])
        
        currentTimeString.addAttribute(NSForegroundColorAttributeName, value: UIColor(red: 0.30, green: 0.69, blue: 0.31, alpha: 1.0), range: .init(location: 0, length: currentTimeString.length))
        
        if async {
            DispatchQueue.main.async {
                self.timeLabel.attributedText = currentTimeString
            }
        } else {
            self.timeLabel.attributedText = currentTimeString
        }
    }
    
    func infoButtonAction() {
        self.view.addSubview(popUpView)
        popUpView.center = self.view.center
        
        popUpView.transform = CGAffineTransform.init(scaleX: 1.3, y: 1.3)
        popUpView.alpha = 0
        
        UIView.animate(withDuration: 0.25) {
            self.view.addSubview(self.visualEffectView)
            
            self.view.bringSubview(toFront: self.popUpView)
            self.popUpView.alpha = 1
            self.popUpView.transform = CGAffineTransform.identity
        }
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return mapName.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = self.popUpTableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! MapKeyCell
        
        cell.mapImage.image = mapImage[indexPath.row]
        cell.mapName.text = mapName[indexPath.row]
        
        if cell.mapName.text == "Inner Stop" {
            cell.mapDirectionImage.image = UIImage.fontAwesomeIcon(name: .repeat, textColor: .black, size: CGSize(width: 50, height: 50))
        } else if cell.mapName.text == "Outer Stop" {
            cell.mapDirectionImage.image = UIImage.fontAwesomeIcon(name: .undo, textColor: .black, size: CGSize(width: 50, height: 50))
        } else {
            cell.mapDirectionImage.image = UIImage()
        }
        
        return cell
    }
    
    //add menu icon to navigation bar
    func addSlideMenuButton(){
        let btnShowMenu = UIButton(type: UIButtonType.system)
        btnShowMenu.setImage(self.defaultMenuImage(), for: UIControlState())
        btnShowMenu.frame = CGRect(x: 0, y: 0, width: 20, height: 25)
        btnShowMenu.addTarget(self.revealViewController(), action: #selector(SWRevealViewController.revealToggle(_:)), for: UIControlEvents.touchUpInside)
        let customBarItem = UIBarButtonItem(customView: btnShowMenu)
        self.navigationItem.leftBarButtonItem = customBarItem;
    }
    
    //Airplane icon
    func addHomeButton() {
        let homeButton = UIButton(type: UIButtonType.system)
        homeButton.setImage(UIImage.fontAwesomeIcon(name: .paperPlaneO, textColor: self.view.tintColor, size: CGSize(width: 30, height: 30)), for: UIControlState())
        homeButton.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        homeButton.addTarget(self, action: #selector(naviToUCSC), for: .touchUpInside)
        
        let customBarItem = UIBarButtonItem(customView: homeButton)
        self.navigationItem.rightBarButtonItem = customBarItem
    }
    
    // triple line menu icon
    func defaultMenuImage() -> UIImage {
        var defaultMenuImage = UIImage()
        
        UIGraphicsBeginImageContextWithOptions(CGSize(width: 20, height: 22), false, 0.0)
        
        UIColor.black.setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 3, width: 20, height: 1)).fill()
        UIBezierPath(rect: CGRect(x: 0, y: 10, width: 20, height: 1)).fill()
        UIBezierPath(rect: CGRect(x: 0, y: 17, width: 20, height: 1)).fill()
        
        UIColor.white.setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 4, width: 20, height: 1)).fill()
        UIBezierPath(rect: CGRect(x: 0, y: 11,  width: 20, height: 1)).fill()
        UIBezierPath(rect: CGRect(x: 0, y: 18, width: 20, height: 1)).fill()
        
        defaultMenuImage = UIGraphicsGetImageFromCurrentImageContext()!
        
        UIGraphicsEndImageContext()
        
        return defaultMenuImage;
    }
    
    class InsetLabel: UILabel {
        var topInset = CGFloat(0)
        var bottomInset = CGFloat(0)
        var leftInset = CGFloat(0)
        var rightInset = CGFloat(0)
        
        init(top: Float, bottom: Float, left: Float, right: Float, rect: CGRect) {
            self.topInset = CGFloat(top)
            self.bottomInset = CGFloat(bottom)
            self.leftInset = CGFloat(left)
            self.rightInset = CGFloat(right)
            super.init(frame: rect)
        }
        
        required init?(coder aDecoder: NSCoder) {
            super.init(coder: aDecoder)
        }
        
        override func drawText(in rect: CGRect) {
            let insets: UIEdgeInsets = UIEdgeInsets(top: topInset, left: leftInset, bottom: bottomInset, right: rightInset)
            
            super.drawText(in: UIEdgeInsetsInsetRect(rect, insets))
        }
        
        override public var intrinsicContentSize: CGSize {
            var intrinsicSuperViewContentSize = super.intrinsicContentSize
            
            intrinsicSuperViewContentSize.height += topInset + bottomInset
            intrinsicSuperViewContentSize.width += leftInset + rightInset
            
            return intrinsicSuperViewContentSize
        }
    }
    
    func revealController(_ revealController: SWRevealViewController!, willMoveTo position: FrontViewPosition) {
        if(position == FrontViewPosition.left) {
            self.mapView.isUserInteractionEnabled = true
        } else {
            self.mapView.isUserInteractionEnabled = false
        }
    }
    
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        view.layer.zPosition = 2
    }
    
    func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
        if let mView = view.annotation as? MapMarker, let z = mView.zOrder {
            view.layer.zPosition = z
        }
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        
        //Check if annotation is user location
        if annotation is MKUserLocation {
            return nil
        }
        
        
        //College/Library Markers Configuration
        //https://stackoverflow.com/questions/29049097/viewforannotation-sometimes-cant-get-custom-mkannotation-class-and-render-it-pr
        if let MapLabel = annotation as? MapLabel {
            
            //Configure Map Label Views
            var width = 0
            var height = 0
            var textColor = UIColor.black
            
            switch (MapLabel.id) {
            case 0:
                width = 30
                height = 25
                textColor = UIColor.blue
            case 1:
                width = 35
                height = 25
                textColor = UIColor.blue
            case 2:
                width = 40
                height = 25
                textColor = UIColor.blue
            case 3:
                width = 40
                height = 25
                textColor = UIColor.black
            case 6:
                width = 30
                height = 30
                textColor = UIColor.blue
            case 9:
                width = 30
                height = 25
                textColor = UIColor.black
            case 10:
                width = 35
                height = 25
                textColor = UIColor.black
            case 11:
                width = 35
                height = 30
                textColor = UIColor.blue
            default:
                print("")
            }
            
            let attributes = [NSStrokeWidthAttributeName: -3.0,
                              NSStrokeColorAttributeName: textColor,
                              NSForegroundColorAttributeName: textColor] as [String : Any]
            
            //Annotation Configuration
            let annotationIdentifier = "MapLabelAnno"
            
            var annotationView: MKAnnotationView?
            
            if let dequeuedAnnotationView = mapView.dequeueReusableAnnotationView(withIdentifier: annotationIdentifier) {
                annotationView = dequeuedAnnotationView
                annotationView?.annotation = annotation
            } else {
                annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: annotationIdentifier)
                
                let labelText = UILabel()
                labelText.tag = 2
                annotationView?.addSubview(labelText)
            }
            
            if let annoView = annotationView?.viewWithTag(2) as? UILabel {
                annotationView?.canShowCallout = true
                annoView.frame = CGRect(x: (-1 * width)/2, y: (-1 * height)/2, width: width, height: height)
                annoView.font = annoView.font.withSize(7)
                annoView.numberOfLines = 5
                annoView.attributedText = NSAttributedString(string: MapLabel.title!, attributes: attributes)
            }
            
            return annotationView
        }
        
        
        // Better to make this class property
        let annotationIdentifier = "AnnotationIdentifier"
        
        var annotationView: MKAnnotationView?
        
        if let dequeuedAnnotationView = mapView.dequeueReusableAnnotationView(withIdentifier: annotationIdentifier) {
            annotationView = dequeuedAnnotationView
            annotationView?.annotation = annotation
        } else {
            annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: annotationIdentifier)
        }
        
        if let annotationView = annotationView {
            annotationView.canShowCallout = true
            
            if let MapMarker = annotation as? MapMarker {
                annotationView.image = MapMarker.image
                annotationView.layer.zPosition = MapMarker.zOrder!
            }
        }
        
        return annotationView
    }
    
    //Checks if user has internet
    //https://stackoverflow.com/questions/30743408/check-for-internet-connection-with-swift
    func isConnectedToNetwork() -> Bool {
        
        var zeroAddress = sockaddr_in(sin_len: 0, sin_family: 0, sin_port: 0, sin_addr: in_addr(s_addr: 0), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        zeroAddress.sin_len = UInt8(MemoryLayout.size(ofValue: zeroAddress))
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        let defaultRouteReachability = withUnsafePointer(to: &zeroAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {zeroSockAddress in
                SCNetworkReachabilityCreateWithAddress(nil, zeroSockAddress)
            }
        }
        
        var flags: SCNetworkReachabilityFlags = SCNetworkReachabilityFlags(rawValue: 0)
        if SCNetworkReachabilityGetFlags(defaultRouteReachability!, &flags) == false {
            return false
        }
        
        /* Only Working for WIFI
         let isReachable = flags == .reachable
         let needsConnection = flags == .connectionRequired
         
         return isReachable && !needsConnection
         */
        
        // Working for Cellular and WIFI
        let isReachable = (flags.rawValue & UInt32(kSCNetworkFlagsReachable)) != 0
        let needsConnection = (flags.rawValue & UInt32(kSCNetworkFlagsConnectionRequired)) != 0
        let ret = (isReachable && !needsConnection)
        
        return ret
        
    }
    
}
