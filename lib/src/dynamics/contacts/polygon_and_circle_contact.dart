part of box2d;

class PolygonAndCircleContact extends Contact {
  PolygonAndCircleContact(IWorldPool argPool) : super(argPool);

  void init0(Fixture fixtureA, Fixture fixtureB) {
    init(fixtureA, 0, fixtureB, 0);
    assert(_fixtureA.getType() == ShapeType.POLYGON);
    assert(_fixtureB.getType() == ShapeType.CIRCLE);
  }

  void evaluate(Manifold manifold, Transform xfA, Transform xfB) {
    Collision().collidePolygonAndCircle(
        manifold,
        _fixtureA.getShape() as PolygonShape,
        xfA,
        _fixtureB.getShape() as CircleShape,
        xfB);
  }
}
