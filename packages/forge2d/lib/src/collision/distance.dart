import 'dart:math';

import 'package:forge2d/forge2d.dart';
import 'package:forge2d/src/settings.dart' as settings;

/// GJK using Voronoi regions (Christer Ericson) and Barycentric coordinates.
class _SimplexVertex {
  final Vector2 wA = Vector2.zero(); // support point in shapeA
  final Vector2 wB = Vector2.zero(); // support point in shapeB
  final Vector2 w = Vector2.zero(); // wB - wA
  double a = 0.0; // barycentric coordinate for closest point
  int indexA = 0; // wA index
  int indexB = 0; // wB index

  void set(_SimplexVertex sv) {
    wA.setFrom(sv.wA);
    wB.setFrom(sv.wB);
    w.setFrom(sv.w);
    a = sv.a;
    indexA = sv.indexA;
    indexB = sv.indexB;
  }
}

class SimplexCache {
  /// length or area
  double metric = 0.0;
  int count = 0;

  /// vertices on shape A
  final List<int> indexA = List<int>.filled(3, 0);

  /// vertices on shape B
  final List<int> indexB = List<int>.filled(3, 0);

  SimplexCache() {
    indexA[0] = settings.intMaxValue;
    indexA[1] = settings.intMaxValue;
    indexA[2] = settings.intMaxValue;
    indexB[0] = settings.intMaxValue;
    indexB[1] = settings.intMaxValue;
    indexB[2] = settings.intMaxValue;
  }

  void set(SimplexCache sc) {
    indexA.setRange(0, sc.indexA.length, sc.indexA);
    indexA.setRange(0, sc.indexB.length, sc.indexB);
    metric = sc.metric;
    count = sc.count;
  }
}

class _Simplex {
  final List<_SimplexVertex> vertices = List<_SimplexVertex>.generate(
    3,
    (_) => _SimplexVertex(),
  );
  _SimplexVertex get vertex1 => vertices[0];
  _SimplexVertex get vertex2 => vertices[1];
  _SimplexVertex get vertex3 => vertices[2];
  int count = 0;

  void readCache(
    SimplexCache cache,
    DistanceProxy proxyA,
    Transform transformA,
    DistanceProxy proxyB,
    Transform transformB,
  ) {
    assert(cache.count <= 3);

    // Copy data from cache.
    count = cache.count;

    for (var i = 0; i < count; ++i) {
      final v = vertices[i];
      v.indexA = cache.indexA[i];
      v.indexB = cache.indexB[i];
      final wALocal = proxyA.getVertex(v.indexA);
      final wBLocal = proxyB.getVertex(v.indexB);
      Transform.mulVec2(transformA, wALocal, out: v.wA);
      Transform.mulVec2(transformB, wBLocal, out: v.wB);
      v.w
        ..setFrom(v.wB)
        ..sub(v.wA);
      v.a = 0.0;
    }

    // Compute the new simplex metric, if it is substantially different than
    // old metric then flush the simplex.
    if (count > 1) {
      final metric1 = cache.metric;
      final metric2 = getMetric();
      if (metric2 < 0.5 * metric1 ||
          2.0 * metric1 < metric2 ||
          metric2 < settings.epsilon) {
        // Reset the simplex.
        count = 0;
      }
    }

    // If the cache is empty or invalid ...
    if (count == 0) {
      final v = vertices[0];
      v.indexA = 0;
      v.indexB = 0;
      final wALocal = proxyA.getVertex(0);
      final wBLocal = proxyB.getVertex(0);
      Transform.mulVec2(transformA, wALocal, out: v.wA);
      Transform.mulVec2(transformB, wBLocal, out: v.wB);
      v.w
        ..setFrom(v.wB)
        ..sub(v.wA);
      count = 1;
    }
  }

  void writeCache(SimplexCache cache) {
    cache.metric = getMetric();
    cache.count = count;

    for (var i = 0; i < count; ++i) {
      cache.indexA[i] = vertices[i].indexA;
      cache.indexB[i] = vertices[i].indexB;
    }
  }

  final Vector2 _e12 = Vector2.zero();

  void getSearchDirection(Vector2 out) {
    switch (count) {
      case 1:
        out
          ..setFrom(vertex1.w)
          ..negate();
        return;
      case 2:
        _e12
          ..setFrom(vertex2.w)
          ..sub(vertex1.w);
        // use out for a temp variable real quick
        out
          ..setFrom(vertex1.w)
          ..negate();
        final sgn = _e12.cross(out);

        if (sgn > 0.0) {
          // Origin is left of e12.
          _e12.scaleOrthogonalInto(1.0, out);
        } else {
          // Origin is right of e12.
          _e12.scaleOrthogonalInto(-1.0, out);
        }
        return;
      default:
        assert(false);
        out.setZero();
        return;
    }
  }

  // djm pooled
  final Vector2 _case2 = Vector2.zero();
  final Vector2 _case22 = Vector2.zero();

  /// This returns pooled objects. don't keep or modify them
  void getClosestPoint(Vector2 out) {
    switch (count) {
      case 0:
        assert(false);
        out.setZero();
        return;
      case 1:
        out.setFrom(vertex1.w);
        return;
      case 2:
        _case22
          ..setFrom(vertex2.w)
          ..scale(vertex2.a);
        _case2
          ..setFrom(vertex1.w)
          ..scale(vertex1.a)
          ..add(_case22);
        out.setFrom(_case2);
        return;
      case 3:
        out.setZero();
        return;
      default:
        assert(false);
        out.setZero();
        return;
    }
  }

  // djm pooled, and from above
  final Vector2 _case3 = Vector2.zero();
  final Vector2 _case33 = Vector2.zero();

  void getWitnessPoints(Vector2 pA, Vector2 pB) {
    switch (count) {
      case 0:
        assert(false);
        break;
      case 1:
        pA.setFrom(vertex1.wA);
        pB.setFrom(vertex1.wB);
        break;
      case 2:
        _case2
          ..setFrom(vertex1.wA)
          ..scale(vertex1.a);
        pA
          ..setFrom(vertex2.wA)
          ..scale(vertex2.a)
          ..add(_case2);
        // v1.a * v1.wA + v2.a * v2.wA;
        // *pB = v1.a * v1.wB + v2.a * v2.wB;
        _case2
          ..setFrom(vertex1.wB)
          ..scale(vertex1.a);
        pB
          ..setFrom(vertex2.wB)
          ..scale(vertex2.a)
          ..add(_case2);

        break;
      case 3:
        pA
          ..setFrom(vertex1.wA)
          ..scale(vertex1.a);
        _case3
          ..setFrom(vertex2.wA)
          ..scale(vertex2.a);
        _case33
          ..setFrom(vertex3.wA)
          ..scale(vertex3.a);
        pA
          ..add(_case3)
          ..add(_case33);
        pB.setFrom(pA);
        break;
      default:
        assert(false);
        break;
    }
  }

  // djm pooled, from above
  double getMetric() {
    switch (count) {
      case 0:
        assert(false);
        return 0.0;
      case 1:
        return 0.0;
      case 2:
        return vertex1.w.distanceTo(vertex2.w);
      case 3:
        _case3
          ..setFrom(vertex2.w)
          ..sub(vertex1.w);
        _case33
          ..setFrom(vertex3.w)
          ..sub(vertex1.w);
        // return Vec2.cross(v2.w - v1.w, v3.w - v1.w);
        return _case3.cross(_case33);
      default:
        assert(false);
        return 0.0;
    }
  }

  /// Solve a line segment using barycentric coordinates.
  void solve2() {
    // Solve a line segment using barycentric coordinates.
    //
    // p = a1 * w1 + a2 * w2
    // a1 + a2 = 1
    //
    // The vector from the origin to the closest point on the line is
    // perpendicular to the line.
    // e12 = w2 - w1
    // dot(p, e) = 0
    // a1 * dot(w1, e) + a2 * dot(w2, e) = 0
    //
    // 2-by-2 linear system
    // [1 1 ][a1] = [1]
    // [w1.e12 w2.e12][a2] = [0]
    //
    // Define
    // d12_1 = dot(w2, e12)
    // d12_2 = -dot(w1, e12)
    // d12 = d12_1 + d12_2
    //
    // Solution
    // a1 = d12_1 / d12
    // a2 = d12_2 / d12
    final w1 = vertex1.w;
    final w2 = vertex2.w;
    _e12
      ..setFrom(w2)
      ..sub(w1);

    // w1 region
    final d12n2 = -w1.dot(_e12);
    if (d12n2 <= 0.0) {
      // a2 <= 0, so we clamp it to 0
      vertex1.a = 1.0;
      count = 1;
      return;
    }

    // w2 region
    final d12n1 = w2.dot(_e12);
    if (d12n1 <= 0.0) {
      // a1 <= 0, so we clamp it to 0
      vertex2.a = 1.0;
      count = 1;
      vertex1.set(vertex2);
      return;
    }

    // Must be in e12 region.
    final invD12 = 1.0 / (d12n1 + d12n2);
    vertex1.a = d12n1 * invD12;
    vertex2.a = d12n2 * invD12;
    count = 2;
  }

  // djm pooled, and from above
  final Vector2 _e13 = Vector2.zero();
  final Vector2 _e23 = Vector2.zero();
  final Vector2 _w1 = Vector2.zero();
  final Vector2 _w2 = Vector2.zero();
  final Vector2 _w3 = Vector2.zero();

  /// Solve a line segment using barycentric coordinates.<br/>
  /// Possible regions:<br/>
  /// - points[2]<br/>
  /// - edge points[0]-points[2]<br/>
  /// - edge points[1]-points[2]<br/>
  /// - inside the triangle
  void solve3() {
    _w1.setFrom(vertex1.w);
    _w2.setFrom(vertex2.w);
    _w3.setFrom(vertex3.w);

    // Edge12
    // [1 1 ][a1] = [1]
    // [w1.e12 w2.e12][a2] = [0]
    // a3 = 0
    _e12
      ..setFrom(_w2)
      ..sub(_w1);
    final w1e12 = _w1.dot(_e12);
    final w2e12 = _w2.dot(_e12);
    final d12n1 = w2e12;
    final d12n2 = -w1e12;

    // Edge13
    // [1 1 ][a1] = [1]
    // [w1.e13 w3.e13][a3] = [0]
    // a2 = 0
    _e13
      ..setFrom(_w3)
      ..sub(_w1);
    final w1e13 = _w1.dot(_e13);
    final w3e13 = _w3.dot(_e13);
    final d13n1 = w3e13;
    final d13n2 = -w1e13;

    // Edge23
    // [1 1 ][a2] = [1]
    // [w2.e23 w3.e23][a3] = [0]
    // a1 = 0
    _e23
      ..setFrom(_w3)
      ..sub(_w2);
    final w2e23 = _w2.dot(_e23);
    final w3e23 = _w3.dot(_e23);
    final d23n1 = w3e23;
    final d23n2 = -w2e23;

    // Triangle123
    final n123 = _e12.cross(_e13);

    final d123n1 = n123 * _w2.cross(_w3);
    final d123n2 = n123 * _w3.cross(_w1);
    final d123n3 = n123 * _w1.cross(_w2);

    // w1 region
    if (d12n2 <= 0.0 && d13n2 <= 0.0) {
      vertex1.a = 1.0;
      count = 1;
      return;
    }

    // e12
    if (d12n1 > 0.0 && d12n2 > 0.0 && d123n3 <= 0.0) {
      final invD12 = 1.0 / (d12n1 + d12n2);
      vertex1.a = d12n1 * invD12;
      vertex2.a = d12n2 * invD12;
      count = 2;
      return;
    }

    // e13
    if (d13n1 > 0.0 && d13n2 > 0.0 && d123n2 <= 0.0) {
      final invD13 = 1.0 / (d13n1 + d13n2);
      vertex1.a = d13n1 * invD13;
      vertex3.a = d13n2 * invD13;
      count = 2;
      vertex2.set(vertex3);
      return;
    }

    // w2 region
    if (d12n1 <= 0.0 && d23n2 <= 0.0) {
      vertex2.a = 1.0;
      count = 1;
      vertex1.set(vertex2);
      return;
    }

    // w3 region
    if (d13n1 <= 0.0 && d23n1 <= 0.0) {
      vertex3.a = 1.0;
      count = 1;
      vertex1.set(vertex3);
      return;
    }

    // e23
    if (d23n1 > 0.0 && d23n2 > 0.0 && d123n1 <= 0.0) {
      final invD23 = 1.0 / (d23n1 + d23n2);
      vertex2.a = d23n1 * invD23;
      vertex3.a = d23n2 * invD23;
      count = 2;
      vertex1.set(vertex3);
      return;
    }

    // Must be in triangle123
    final invD123 = 1.0 / (d123n1 + d123n2 + d123n3);
    vertex1.a = d123n1 * invD123;
    vertex2.a = d123n2 * invD123;
    vertex3.a = d123n3 * invD123;
    count = 3;
  }
} // Class _Simplex

class DistanceProxy {
  final List<Vector2> vertices = List<Vector2>.generate(
    settings.maxPolygonVertices,
    (_) => Vector2.zero(),
  );
  int _count = 0;
  double radius = 0.0;
  final List<Vector2> buffer = List<Vector2>.generate(2, (_) => Vector2.zero());

  /// Initialize the proxy using the given shape. The shape must remain in scope
  /// while the proxy is in use.
  void set(Shape shape, int index) {
    switch (shape.shapeType) {
      case ShapeType.circle:
        final circle = shape as CircleShape;
        vertices[0].setFrom(circle.position);
        _count = 1;
        radius = circle.radius;

        break;
      case ShapeType.polygon:
        final poly = shape as PolygonShape;
        _count = poly.vertices.length;
        radius = poly.radius;
        for (var i = 0; i < _count; i++) {
          vertices[i].setFrom(poly.vertices[i]);
        }
        break;
      case ShapeType.chain:
        final chain = shape as ChainShape;
        assert(0 <= index && index < chain.vertexCount);

        buffer[0] = chain.vertices[index];
        if (index + 1 < chain.vertexCount) {
          buffer[1] = chain.vertices[index + 1];
        } else {
          buffer[1] = chain.vertices[0];
        }

        vertices[0].setFrom(buffer[0]);
        vertices[1].setFrom(buffer[1]);
        _count = 2;
        radius = chain.radius;
        break;
      case ShapeType.edge:
        final edge = shape as EdgeShape;
        vertices[0].setFrom(edge.vertex1);
        vertices[1].setFrom(edge.vertex2);
        _count = 2;
        radius = edge.radius;
        break;
    }
  }

  /// Get the supporting vertex index in the given direction.
  int getSupport(Vector2 d) {
    var bestIndex = 0;
    var bestValue = vertices[0].dot(d);
    for (var i = 1; i < _count; i++) {
      final value = vertices[i].dot(d);
      if (value > bestValue) {
        bestIndex = i;
        bestValue = value;
      }
    }

    return bestIndex;
  }

  /// Get the supporting vertex in the given direction.
  Vector2 getSupportVertex(Vector2 d) {
    var bestIndex = 0;
    var bestValue = vertices[0].dot(d);
    for (var i = 1; i < _count; i++) {
      final value = vertices[i].dot(d);
      if (value > bestValue) {
        bestIndex = i;
        bestValue = value;
      }
    }

    return vertices[bestIndex];
  }

  /// Get the vertex count.
  int getVertexCount() {
    return _count;
  }

  /// Get a vertex by index. Used by Distance.
  Vector2 getVertex(int index) {
    assert(0 <= index && index < _count);
    return vertices[index];
  }
} // Class _DistanceProxy.

class Distance {
  static const int maxIterations = 20;

  static int gjkCalls = 0;
  static int gjkIterations = 0;
  static int gjkMaxIterations = 20;

  final _Simplex _simplex = _Simplex();
  final List<int> _saveA = List<int>.filled(3, 0);
  final List<int> _saveB = List<int>.filled(3, 0);
  final Vector2 _closestPoint = Vector2.zero();
  final Vector2 _d = Vector2.zero();
  final Vector2 _temp = Vector2.zero();
  final Vector2 _normal = Vector2.zero();

  /// Compute the closest points between two shapes. Supports any combination
  /// of: CircleShape and PolygonShape. The simplex cache is input/output.
  /// On the first call set [SimplexCache.count] to zero.
  void compute(
    DistanceOutput output,
    SimplexCache cache,
    DistanceInput input,
  ) {
    gjkCalls++;

    final proxyA = input.proxyA;
    final proxyB = input.proxyB;

    final transformA = input.transformA;
    final transformB = input.transformB;

    // Initialize the simplex.
    _simplex.readCache(cache, proxyA, transformA, proxyB, transformB);

    // Get simplex vertices as an array.
    final vertices = _simplex.vertices;

    // These store the vertices of the last simplex so that we
    // can check for duplicates and prevent cycling.
    // (pooled above)
    var saveCount = 0;

    _simplex.getClosestPoint(_closestPoint);
    var distanceSqr1 = _closestPoint.length2;
    var distanceSqr2 = distanceSqr1;

    // Main iteration loop
    var iter = 0;
    while (iter < maxIterations) {
      // Copy simplex so we can identify duplicates.
      saveCount = _simplex.count;
      for (var i = 0; i < saveCount; i++) {
        _saveA[i] = vertices[i].indexA;
        _saveB[i] = vertices[i].indexB;
      }

      switch (_simplex.count) {
        case 1:
          break;
        case 2:
          _simplex.solve2();
          break;
        case 3:
          _simplex.solve3();
          break;
        default:
          assert(false);
      }

      // If we have 3 points, then the origin is in the corresponding triangle.
      if (_simplex.count == 3) {
        break;
      }

      // Compute closest point.
      _simplex.getClosestPoint(_closestPoint);
      distanceSqr2 = _closestPoint.length2;

      // ensure progress
      if (distanceSqr2 >= distanceSqr1) {
        // break;
      }
      distanceSqr1 = distanceSqr2;

      // get search direction;
      _simplex.getSearchDirection(_d);

      // Ensure the search direction is numerically fit.
      if (_d.length2 < settings.epsilon * settings.epsilon) {
        // The origin is probably contained by a line segment
        // or triangle. Thus the shapes are overlapped.

        // We can't return zero here even though there may be overlap.
        // In case the simplex is a point, segment, or triangle it is difficult
        // to determine if the origin is contained in the CSO or very close to
        // it.
        break;
      }
      /*
       * SimplexVertex* vertex = vertices + simplex.count; vertex.indexA =
       * proxyA.GetSupport(MulT(transformA.R, -d)); vertex.wA = Mul(transformA,
       * proxyA.GetVertex(vertex.indexA)); Vec2 wBLocal; vertex.indexB =
       * proxyB.GetSupport(MulT(transformB.R, d)); vertex.wB = Mul(transformB,
       * proxyB.GetVertex(vertex.indexB)); vertex.w = vertex.wB - vertex.wA;
       */

      // Compute a tentative new simplex vertex using support points.
      final vertex = vertices[_simplex.count];

      Rot.mulTransVec2(transformA.q, _d..negate(), out: _temp);
      vertex.indexA = proxyA.getSupport(_temp);
      Transform.mulVec2(transformA, proxyA.getVertex(vertex.indexA),
          out: vertex.wA);
      // Vec2 wBLocal;
      Rot.mulTransVec2(transformB.q, _d..negate(), out: _temp);
      vertex.indexB = proxyB.getSupport(_temp);
      Transform.mulVec2(transformB, proxyB.getVertex(vertex.indexB),
          out: vertex.wB);
      (vertex.w..setFrom(vertex.wB)).sub(vertex.wA);

      // Iteration count is equated to the number of support point calls.
      ++iter;
      ++gjkIterations;

      // Check for duplicate support points. This is the main termination
      // criteria.
      var duplicate = false;
      for (var i = 0; i < saveCount; ++i) {
        if (vertex.indexA == _saveA[i] && vertex.indexB == _saveB[i]) {
          duplicate = true;
          break;
        }
      }

      // If we found a duplicate support point we must exit to avoid cycling.
      if (duplicate) {
        break;
      }

      // New vertex is ok and needed.
      ++_simplex.count;
    }

    gjkMaxIterations = max(gjkMaxIterations, iter);

    // Prepare output.
    _simplex.getWitnessPoints(output.pointA, output.pointB);
    output.distance = output.pointA.distanceTo(output.pointB);
    output.iterations = iter;

    // Cache the simplex.
    _simplex.writeCache(cache);

    // Apply radii if requested.
    if (input.useRadii) {
      final rA = proxyA.radius;
      final rB = proxyB.radius;

      if (output.distance > rA + rB && output.distance > settings.epsilon) {
        // Shapes are still no overlapped.
        // Move the witness points to the outer surface.
        output.distance -= rA + rB;
        _normal
          ..setFrom(output.pointB)
          ..sub(output.pointA);
        _normal.normalize();
        _temp
          ..setFrom(_normal)
          ..scale(rA);
        output.pointA.add(_temp);
        _temp
          ..setFrom(_normal)
          ..scale(rB);
        output.pointB.sub(_temp);
      } else {
        // Shapes are overlapped when radii are considered.
        // Move the witness points to the middle.
        // Vec2 p = 0.5f * (output.pointA + output.pointB);
        output.pointA
          ..add(output.pointB)
          ..scale(.5);
        output.pointB.setFrom(output.pointA);
        output.distance = 0.0;
      }
    }
  }
}
