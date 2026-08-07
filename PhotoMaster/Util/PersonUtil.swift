import Photos

class PersonUtil {
    private static var allPersons: [Person] = []
    
    /// 人物模型
    struct Person {
        let localIdentifier: String
        let name: String
        let assetCount: Int
    }
    
    /// 获取所有人物
    /// - Returns: 人物数组
    static func fetchAllPersons() -> [Person] {
        print("[PersonUtil] 开始获取所有人物")
        
        // 检查权限
        let status = PHPhotoLibrary.authorizationStatus()
        if status != .authorized && status != .limited {
            print("[PersonUtil] 没有照片权限，无法获取人物列表")
            return []
        }
        
        var persons: [Person] = []
        
        // 获取人物列表
        let options = PHFetchOptions()
        let personCollections = PHCollectionList.fetchCollectionLists(with: .momentList, subtype: .momentListCluster, options: options)
        
        personCollections.enumerateObjects { (collection, _, _) in
            let personCollection = collection
            let name = personCollection.localizedTitle ?? "无名人物"
            
            // 计算人物的照片数量
            var assetCount = 0
            let momentOptions = PHFetchOptions()
            let moments = PHAssetCollection.fetchMoments(inMomentList: personCollection, options: momentOptions)
            
            moments.enumerateObjects { (moment, _, _) in
                let momentAssets = PHAsset.fetchAssets(in: moment, options: nil)
                assetCount += momentAssets.count
            }
            
            let person = Person(localIdentifier: personCollection.localIdentifier, name: name, assetCount: assetCount)
            persons.append(person)
            
            print("[PersonUtil] 找到人物: \(name), 照片数: \(assetCount)")
        }
        
        print("[PersonUtil] 共找到 \(persons.count) 个人物")
        allPersons = persons
        return persons
    }
    
    /// 检查照片是否属于指定人物
    /// - Parameters:
    ///   - asset: 照片资产
    ///   - personNames: 人物名称数组
    /// - Returns: 是否属于指定人物
    static func checkPerson(asset: PHAsset, personNames: [String]) -> Bool {
        // 检查权限
        let status = PHPhotoLibrary.authorizationStatus()
        if status != .authorized && status != .limited {
            return false
        }
        
        // 获取所有人物
        if allPersons.isEmpty {
            _ = fetchAllPersons()
        }
        
        // 遍历人物，检查照片是否在人物的照片集合中
        for person in allPersons {
            if personNames.contains(person.name) {
                let personCollection = PHCollectionList.fetchCollectionLists(withLocalIdentifiers: [person.localIdentifier], options: nil).firstObject
                if let personCollection = personCollection {
                    // 检查照片是否在人物集合中
                    let momentOptions = PHFetchOptions()
                    let moments = PHAssetCollection.fetchMoments(inMomentList: personCollection, options: momentOptions)
                    
                    var found = false
                    moments.enumerateObjects { (moment, _, stop) in
                        let fetchOptions = PHFetchOptions()
                        fetchOptions.predicate = NSPredicate(format: "localIdentifier == %@", asset.localIdentifier)
                        let assets = PHAsset.fetchAssets(in: moment, options: fetchOptions)
                        if assets.count > 0 {
                            found = true
                            stop.pointee = true
                        }
                    }
                    
                    if found {
                        return true
                    }
                }
            }
        }
        
        return false
    }
}
