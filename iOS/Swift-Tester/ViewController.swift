//
//  ViewController.swift
//  Swift-Tester
//
//  Created by karl on 2016-01-28.
//  Copyright © 2016 Karl Stenerud. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func onButtonPressed(_ sender: AnyObject) {
        var emptyDictionary = Dictionary<Int,Int>()
        print(emptyDictionary[1]!)
    }
}

