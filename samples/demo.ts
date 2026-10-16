type UserId = string | number;

interface Repository<TEntity extends { id: UserId }> {
  findById(id: UserId): Promise<TEntity | undefined>;
  save(entity: TEntity): Promise<TEntity>;
  remove(id: UserId): Promise<void>;
}

class UserRepository implements Repository<User> {
  constructor(private readonly db: Database<Postgres>) {}

  async findById(id: UserId): Promise<User | undefined> {
    return this.db.query<User>("select * from users where id = $1", [id]);
  }
}
