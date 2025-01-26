""" Game engine functions.
"""
from utils import unimplemented, assert
from math import sin, cos, tan, radians
from vectype import Vector, new_vector
from screen import Screen

pub class Engine:
    """ 3D engine! """
    var m_screen: Screen
    var m_projection: Mat = new_mat4()

    pub fn set_projection_matrix(fov: float, near: float, far: float):
        let S = 1.0 / tan(radians(degrees: fov / 2.0))
        m_projection.m[0][0] = S
        m_projection.m[1][1] = S
        m_projection.m[2][3] = -1

    pub fn draw_mesh(m: Mesh):
        pass

pub fn new_cube_mesh() -> Mesh:
    let vertici: Vector[Vertex] = new_vector()
    let faces: Vector[Face] = new_vector()
    vertici.append(Vertex(x: -1, y: -1, z: 1))
    vertici.append(Vertex(x: -1, y: 1, z: 1))
    vertici.append(Vertex(x: 1, y: -1, z: 1))
    vertici.append(Vertex(x: 1, y: 1, z: 1))
    let m = Mesh(vertici, faces)
    m

pub fn new_cylinder_mesh() -> Mesh:
    unimplemented("new_cylinder_mesh")


pub fn new_mat4() -> Mat:
    new_mat(rows: 4, cols: 4)

pub fn new_mat(rows: int, cols: int) -> Mat:
    let m = [rows : [float]]
    let row = 0
    while row < rows:
        m[row] = [cols: float]
        let col = 0
        while col < cols:
            m[row][col] = 0.0
            col += 1
        row += 1
    Mat(rows, cols, m)

pub fn matrix_multiply(a: Mat, b: Mat, out: Mat):
    """ Matrix multiplication A*B """
    assert(condition: a.rows == out.rows, message: "Shape mismatch 1")
    assert(condition: a.cols == b.rows, message: "Shape mismatch 2")
    assert(condition: b.cols == out.cols, message: "Shape mismatch 3")
    let row = 0
    while row < out.rows:
        let col = 0
        while col < out.cols:
            let sum = 0.0
            let i = 0
            while i < a.cols:
                sum += a.m[row][i] * b.m[i][col]
                i += 1
            out.m[row][col] = sum
            col += 1
        row += 1

pub fn matrix_vec_multiply(mat: Mat, vec: Vertex) -> Vertex:
    let out = new_vertex()
    out.x = mat.m[0][0] * vec.x + mat.m[1][0] * vec.y + mat.m[2][0] * vec.z + mat.m[3][0]
    out.y = mat.m[0][1] * vec.x + mat.m[1][1] * vec.y + mat.m[2][1] * vec.z + mat.m[3][1]
    out.z = mat.m[0][2] * vec.x + mat.m[1][2] * vec.y + mat.m[2][2] * vec.z + mat.m[3][2]
    let w = mat.m[0][3] * vec.x + mat.m[1][3] * vec.y + mat.m[2][3] * vec.z + mat.m[3][3]
    out.x /= w
    out.y /= w
    out.z /= w
    out

pub fn rotx(theta: float) -> Mat:
    """ Rotation matrix around the x axis. """
    let out = new_mat4()
    let c = cos(theta)
    let s = sin(theta)
    out.m[0][0] = 1
    out.m[1][1] = c
    out.m[1][2] = -s
    out.m[2][1] = s
    out.m[2][2] = c
    out

pub fn roty(theta: float) -> Mat:
    """ Rotation matrix around the y axis. """
    let out = new_mat4()
    let c = cos(theta)
    let s = sin(theta)
    out.m[0][0] = c
    out.m[0][2] = s
    out.m[1][1] = 1
    out.m[2][0] = -s
    out.m[2][2] = c
    out

pub fn rotz(theta: float) -> Mat:
    """ Rotation matrix around the z axis. """
    let out = new_mat4()
    let c = cos(theta)
    let s = sin(theta)
    out.m[0][0] = c
    out.m[0][1] = -s
    out.m[1][0] = s
    out.m[1][1] = c
    out.m[2][2] = 1
    out

pub struct Mat:
    rows: int
    cols: int
    m: [[float]]

pub struct VecF:
    size: int
    m: [float]

pub struct Vertex:
    x: float
    y: float
    z: float

pub fn new_vertex() -> Vertex:
    Vertex(x: 0, y: 0, z: 0)

pub class Mesh:
    var vertici: Vector[Vertex]
    var faces: Vector[Face]

pub struct Face:
    v1: int
    v2: int
    v3: int
