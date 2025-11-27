// Created by NoesisNoema on 2023-10-23.
// License: MIT License
// Project: NoesisNoema
// Description: Defines the FileResource class for handling file resources.

import Foundation

class FileResource {

    var filename: String
    var data: Data

    /// Initializes a FileResource with a filename and data.

    init(filename: String, data: Data) {
        self.filename = filename
        self.data = data
    }

}
