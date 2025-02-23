// TODO(any): Rewrite the setters instead of ignoring this lint.
// ignore_for_file: avoid_positional_boolean_parameters

import 'dart:math';

import 'package:forge2d/forge2d.dart';
import 'package:forge2d/src/settings.dart' as settings;
import 'package:meta/meta.dart';

/// A fixture is used to attach a [Shape] to a [Body] for collision detection. A
/// fixture inherits its transform from its parent. Fixtures hold additional
/// non-geometric data such as friction, collision filters, etc. Fixtures are
/// created via `body.createFixture`.
///
/// Do note that you cannot reuse fixtures.
class Fixture {
  double _density = 0.0;

  final Body body;

  late Shape shape;

  double friction = 0.0;
  double restitution = 0.0;

  final List<FixtureProxy> proxies = [];
  int _proxyCount = 0;
  int get proxyCount => _proxyCount;

  final Filter _filter = Filter();

  bool _isSensor = false;

  /// Use this to store your application specific data.
  Object? userData;

  /// Get the type of the child shape. You can use this to down cast to the
  /// concrete shape.
  ShapeType get type => shape.shapeType;

  /// Is this fixture a sensor (non-solid)?
  bool get isSensor => _isSensor;

  /// Set if this fixture is a sensor.
  void setSensor(bool sensor) {
    if (sensor != _isSensor) {
      body.setAwake(true);
      _isSensor = sensor;
    }
  }

  /// Set the contact filtering data. This is an expensive operation and should
  /// not be called frequently. This will not update contacts until the next
  /// time step when either parent body is awake. This automatically calls
  /// [refilter].
  set filterData(Filter filter) {
    _filter.set(filter);
    refilter();
  }

  /// Get the contact filtering data.
  Filter get filterData => _filter;

  /// Call this if you want to establish collision that was previously disabled
  /// by [ContactFilter.shouldCollide].
  void refilter() {
    // Flag associated contacts for filtering.
    for (final contact in body.contacts) {
      final fixtureA = contact.fixtureA;
      final fixtureB = contact.fixtureB;
      if (fixtureA == this || fixtureB == this) {
        contact.flagForFiltering();
      }
    }

    // Touch each proxy so that new pairs may be created
    final broadPhase = body.world.contactManager.broadPhase;
    for (var i = 0; i < _proxyCount; ++i) {
      broadPhase.touchProxy(proxies[i].proxyId);
    }
  }

  set density(double density) {
    assert(density >= 0.9);
    _density = density;
  }

  double get density => _density;

  /// Test a point for containment in this fixture. This only works for convex
  /// shapes.
  ///
  /// [point] should be in world coordinates.
  bool testPoint(Vector2 point) {
    return shape.testPoint(body.transform, point);
  }

  /// Cast a ray against this shape.
  bool raycast(RayCastOutput output, RayCastInput input, int childIndex) {
    return shape.raycast(output, input, body.transform, childIndex);
  }

  /// Get the mass data for this fixture. The mass data is based on the density
  /// and the shape. The rotational inertia is about the shape's origin.
  void getMassData(MassData massData) {
    shape.computeMass(massData, _density);
  }

  /// Get the fixture's AABB. This AABB may be enlarge and/or stale. If you
  /// need a more accurate AABB, compute it using the shape and the body
  /// transform.
  AABB getAABB(int childIndex) {
    assert(childIndex >= 0 && childIndex < _proxyCount);
    return proxies[childIndex].aabb;
  }

  /// Compute the distance from this fixture.
  ///
  /// [point] should be in world coordinates.
  double computeDistance(
    Vector2 point,
    int childIndex,
    Vector2 normalOut,
  ) {
    return shape.computeDistanceToOut(
      body.transform,
      point,
      childIndex,
      normalOut,
    );
  }

  Fixture(this.body, FixtureDef def) {
    userData = def.userData;
    friction = def.friction;
    restitution = def.restitution;

    _filter.set(def.filter);

    _isSensor = def.isSensor;

    shape = def.shape.clone();

    // Reserve proxy space
    final childCount = shape.childCount;
    if (proxies.length < childCount) {
      final old = proxies;
      final newLength = max(old.length * 2, childCount);
      proxies.clear();
      for (var x = 0; x < newLength; x++) {
        proxies.add(FixtureProxy(this)..proxyId = BroadPhase.nullProxy);
      }
    }
    _proxyCount = 0;
    _density = def.density;
  }

  // These support body activation/deactivation.
  void createProxies(BroadPhase broadPhase, Transform xf) {
    assert(_proxyCount == 0);

    // Create proxies in the broad-phase.
    _proxyCount = shape.childCount;

    for (var i = 0; i < _proxyCount; ++i) {
      final proxy = proxies[i];
      shape.computeAABB(proxy.aabb, xf, i);
      proxy.proxyId = broadPhase.createProxy(proxy.aabb, proxy);
      proxy.childIndex = i;
    }
  }

  /// Internal method
  void destroyProxies(BroadPhase broadPhase) {
    // Destroy proxies in the broad-phase.
    for (var i = 0; i < _proxyCount; ++i) {
      final proxy = proxies[i];
      broadPhase.destroyProxy(proxy.proxyId);
      proxy.proxyId = BroadPhase.nullProxy;
    }

    _proxyCount = 0;
  }

  final AABB _pool1 = AABB();
  final AABB _pool2 = AABB();
  final Vector2 _displacement = Vector2.zero();

  @internal
  void synchronize(
    BroadPhase broadPhase,
    Transform transform1,
    Transform transform2,
  ) {
    if (_proxyCount == 0) {
      return;
    }

    for (var i = 0; i < _proxyCount; ++i) {
      final proxy = proxies[i];

      // Compute an AABB that covers the swept shape
      // (may miss some rotation effect).
      final aabb1 = _pool1;
      final aab = _pool2;
      shape.computeAABB(aabb1, transform1, proxy.childIndex);
      shape.computeAABB(aab, transform2, proxy.childIndex);

      proxy.aabb.lowerBound.x = aabb1.lowerBound.x < aab.lowerBound.x
          ? aabb1.lowerBound.x
          : aab.lowerBound.x;
      proxy.aabb.lowerBound.y = aabb1.lowerBound.y < aab.lowerBound.y
          ? aabb1.lowerBound.y
          : aab.lowerBound.y;
      proxy.aabb.upperBound.x = aabb1.upperBound.x > aab.upperBound.x
          ? aabb1.upperBound.x
          : aab.upperBound.x;
      proxy.aabb.upperBound.y = aabb1.upperBound.y > aab.upperBound.y
          ? aabb1.upperBound.y
          : aab.upperBound.y;
      _displacement.x = transform2.p.x - transform1.p.x;
      _displacement.y = transform2.p.y - transform1.p.y;

      broadPhase.moveProxy(proxy.proxyId, proxy.aabb, _displacement);
    }
  }

  // NOTE this corresponds to the liquid test, so the debugdraw can draw
  // the liquid particles correctly. They should be the same.
  static const int liquidFlag = 1234598372;
  final double _liquidLength = .12;
  double _averageLinearVel = -1.0;
  final Vector2 _liquidOffset = Vector2.zero();
  final Vector2 _circleCenterMoved = Vector2.zero();
  final Color3i _liquidColor = Color3i.fromRGBd(0.4, .4, 1.0);

  final Vector2 renderCenter = Vector2.zero();
  final Vector2 renderAxis = Vector2.zero();
  final Vector2 _v1 = Vector2.zero();
  final Vector2 _v2 = Vector2.zero();

  void render(
    DebugDraw debugDraw,
    Transform xf,
    Color3i color,
    bool wireframe,
  ) {
    switch (type) {
      case ShapeType.circle:
        {
          final circle = shape as CircleShape;

          renderCenter.setFrom(Transform.mulVec2(xf, circle.position));
          final radius = circle.radius;
          xf.q.getXAxis(out: renderAxis);

          if (userData != null && userData == liquidFlag) {
            _liquidOffset.setFrom(body.linearVelocity);
            final linVelLength = body.linearVelocity.length;
            if (_averageLinearVel == -1) {
              _averageLinearVel = linVelLength;
            } else {
              _averageLinearVel = .98 * _averageLinearVel + .02 * linVelLength;
            }
            _liquidOffset.scale(_liquidLength / _averageLinearVel / 2);
            _circleCenterMoved
              ..setFrom(renderCenter)
              ..add(_liquidOffset);
            renderCenter.sub(_liquidOffset);
            debugDraw.drawSegment(
              renderCenter,
              _circleCenterMoved,
              _liquidColor,
            );
            return;
          }
          if (wireframe) {
            debugDraw.drawCircleAxis(renderCenter, radius, renderAxis, color);
          } else {
            debugDraw.drawSolidCircle(renderCenter, radius, color);
          }
        }
        break;
      case ShapeType.polygon:
        {
          final poly = shape as PolygonShape;
          assert(poly.vertices.length <= settings.maxPolygonVertices);
          final vertices = poly.vertices
              .map(
                (vertex) => Transform.mulVec2(xf, vertex),
              )
              .toList();

          if (wireframe) {
            debugDraw.drawPolygon(vertices, color);
          } else {
            debugDraw.drawSolidPolygon(vertices, color);
          }
        }
        break;
      case ShapeType.edge:
        {
          final edge = shape as EdgeShape;
          _v1.setFrom(Transform.mulVec2(xf, edge.vertex1));
          _v2.setFrom(Transform.mulVec2(xf, edge.vertex2));
          debugDraw.drawSegment(_v1, _v2, color);
        }
        break;
      case ShapeType.chain:
        {
          final chain = shape as ChainShape;
          final count = chain.vertexCount;
          final vertices = chain.vertices;

          _v1.setFrom(Transform.mulVec2(xf, vertices[0]));
          for (var i = 1; i < count; ++i) {
            _v2.setFrom(Transform.mulVec2(xf, vertices[i]));
            debugDraw.drawSegment(_v1, _v2, color);
            debugDraw.drawCircle(_v1, 0.05, color);
            _v1.setFrom(_v2);
          }
        }
        break;
    }
  }
}
