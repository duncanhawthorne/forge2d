import 'package:forge2d/forge2d.dart';

/// A transform contains translation and rotation. It is used to represent the
/// position and orientation of rigid frames.
class Transform {
  /// This is a reusable vector that can be used within [Transform]
  /// to avoid creation of new Vector2 instances.
  ///
  /// Avoid using this in async extension methods, as it can lead to race
  /// conditions.
  static final _reusableVector = Vector2.zero();

  /// The translation caused by the transform
  final Vector2 p;

  /// A matrix representing a rotation
  final Rot q;

  /// The default constructor.
  Transform.zero()
      : p = Vector2.zero(),
        q = Rot();

  /// Initialize as a copy of another transform.
  Transform.clone(Transform xf)
      : p = xf.p.clone(),
        q = xf.q.clone();

  /// Initialize using a position vector and a rotation matrix.
  Transform.from(Vector2 position, Rot r)
      : p = position.clone(),
        q = r.clone();

  /// Set this to equal another transform.
  void setFrom(Transform xf) {
    p.setFrom(xf.p);
    q.setFrom(xf.q);
  }

  /// Set this based on the position and angle.
  void setVec2Angle(Vector2 p, double angle) {
    p.setFrom(p);
    q.setAngle(angle);
  }

  /// Set this to the identity transform.
  void setIdentity() {
    p.setZero();
    q.setIdentity();
  }

  static Vector2 mulVec2(Transform t, Vector2 v, {Vector2? out}) {
    final result = out ?? Vector2.zero();
    return result
      ..setValues((t.q.cos * v.x - t.q.sin * v.y) + t.p.x,
          (t.q.sin * v.x + t.q.cos * v.y) + t.p.y);
  }

  static Vector2 mulTransVec2(Transform t, Vector2 v, {Vector2? out}) {
    final pX = v.x - t.p.x;
    final pY = v.y - t.p.y;
    final result = out ?? Vector2.zero();
    return result
      ..setValues(t.q.cos * pX + t.q.sin * pY, -t.q.sin * pX + t.q.cos * pY);
  }

  factory Transform.mul(Transform a, Transform b) {
    final c = Transform.zero();
    c.q.setFrom(Rot.mul(a.q, b.q));
    Rot.mulVec2(a.q, b.p, out: c.p);
    c.p.add(a.p);
    return c;
  }

  factory Transform.mulTrans(Transform a, Transform b, {Transform? out}) {
    _reusableVector
      ..setFrom(b.p)
      ..sub(a.p);
    Rot.mulTransVec2(a.q, _reusableVector, out: _reusableVector);
    final result = out ?? Transform.zero();
    return result
      ..p.setFrom(_reusableVector)
      ..q.setFrom(Rot.mulTrans(a.q, b.q));
  }

  @override
  String toString() {
    var s = 'XForm:\n';
    s += 'Position: $p\n';
    s += 'R: \t$q\n';
    return s;
  }
}
