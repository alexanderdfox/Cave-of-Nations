//
//  SceneKitExtensions.swift
//  CaveOfNationsApp
//
//  Utility overloads and helpers for concise vector math inside GameWorld.
//

import SceneKit

func +(lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
    SCNVector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
}

func -(lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
    SCNVector3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
}

func *(lhs: SCNVector3, rhs: CGFloat) -> SCNVector3 {
    SCNVector3(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs)
}

func *(lhs: CGFloat, rhs: SCNVector3) -> SCNVector3 {
    rhs * lhs
}

extension SCNVector3 {
    static let zeroVector = SCNVector3Zero
}
