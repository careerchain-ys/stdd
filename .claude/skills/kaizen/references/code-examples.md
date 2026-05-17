# Kaizen コード例集

SKILL.md本体の4つの柱に対応する詳細なコード例。

## 目次

- [継続的改善のコード例](#継続的改善のコード例)
- [Poka-Yokeのコード例](#poka-yokeのコード例)
- [JIT/YAGNIのコード例](#jityagniのコード例)

---

## 継続的改善のコード例

### 段階的リファクタリング

```typescript
// Iteration 1: まず動くものを作る
const calculateTotal = (items: Item[]) => {
  let total = 0;
  for (let i = 0; i < items.length; i++) {
    total += items[i].price * items[i].quantity;
  }
  return total;
};

// Iteration 2: 明確にする（リファクタ）
const calculateTotal = (items: Item[]): number => {
  return items.reduce((total, item) => {
    return total + (item.price * item.quantity);
  }, 0);
};

// Iteration 3: 堅牢にする（バリデーション追加）
const calculateTotal = (items: Item[]): number => {
  if (!items?.length) return 0;

  return items.reduce((total, item) => {
    if (item.price < 0 || item.quantity < 0) {
      throw new Error('Price and quantity must be non-negative');
    }
    return total + (item.price * item.quantity);
  }, 0);
};
```

各ステップが完結しており、テスト可能。一度にすべてやろうとしない。

### 悪い例: 一度にすべてやろうとする

```typescript
const calculateTotal = (items: Item[]): number => {
  if (!items?.length) return 0;
  const validItems = items.filter(item => {
    if (item.price < 0) throw new Error('Negative price');
    if (item.quantity < 0) throw new Error('Negative quantity');
    return item.quantity > 0;
  });
  // キャッシュも、ロギングも、通貨変換も一度に…
  return validItems.reduce(...);
};
```

---

## Poka-Yokeのコード例

### 型システムによるエラー防止

```typescript
// 悪い例: stringで状態管理
type OrderBad = {
  status: string; // "pending", "PENDING", "pnding" 何でも入る
  total: number;
};

// 良い例: Union Typeで制約
type OrderStatus = 'pending' | 'processing' | 'shipped' | 'delivered';
type Order = {
  status: OrderStatus;
  total: number;
};

// より良い例: 状態に応じたデータを強制
type Order =
  | { status: 'pending'; createdAt: Date }
  | { status: 'processing'; startedAt: Date; estimatedCompletion: Date }
  | { status: 'shipped'; trackingNumber: string; shippedAt: Date }
  | { status: 'delivered'; deliveredAt: Date; signature: string };
// shipped状態ではtrackingNumberが必須になる
```

### バリデーションの境界防御

```typescript
// 悪い例: バリデーション前に使用
const processPayment = (amount: number) => {
  const fee = amount * 0.03; // バリデーション前に使っている
  if (amount <= 0) throw new Error('Invalid amount');
};

// 良い例: 境界でバリデーション、以降は安全
const processPayment = (amount: number) => {
  if (amount <= 0) {
    throw new Error('Payment amount must be positive');
  }
  const fee = amount * 0.03;
};
```

### ガード節（Early Return）

```typescript
const processUser = (user: User | null) => {
  if (!user) {
    logger.error('User not found');
    return;
  }

  if (!user.email) {
    logger.error('User email missing');
    return;
  }

  if (!user.isActive) {
    logger.info('User inactive, skipping');
    return;
  }

  // ここに到達 = userは有効かつアクティブであることが保証される
  sendEmail(user.email, 'Welcome!');
};
```

### 設定のエラー防止

```typescript
// 悪い例: optionalで起動時にチェックしない
type ConfigBad = {
  apiKey?: string;
  timeout?: number;
};

// 良い例: 必須にして起動時に検証
type Config = {
  apiKey: string;
  timeout: number;
};

const loadConfig = (): Config => {
  const apiKey = process.env.API_KEY;
  if (!apiKey) {
    throw new Error('API_KEY environment variable required');
  }
  return { apiKey, timeout: 5000 };
};

// アプリ起動時に失敗する（リクエスト中ではなく）
const config = loadConfig();
```

---

## JIT/YAGNIのコード例

### 過剰設計の例

```typescript
// 悪い例: 「将来必要かもしれない」で過剰設計
interface LogTransport {
  write(level: LogLevel, message: string, meta?: LogMetadata): Promise<void>;
}
class ConsoleTransport implements LogTransport { /* ... */ }
class FileTransport implements LogTransport { /* ... */ }
class RemoteTransport implements LogTransport { /* ... */ }
class Logger {
  private transports: LogTransport[] = [];
  private queue: LogEntry[] = [];
  // 200行のコード…
}

// 良い例: 今必要なものだけ
const logError = (error: Error) => {
  console.error(error.message);
};
```

### 段階的な複雑化

```typescript
// Step 1: シンプルに始める
const formatCurrency = (amount: number): string => {
  return `$${amount.toFixed(2)}`;
};

// Step 2: 要件が増えたら対応（複数通貨）
const formatCurrency = (amount: number, currency: string): string => {
  const symbols = { USD: '$', EUR: '€', GBP: '£' };
  return `${symbols[currency]}${amount.toFixed(2)}`;
};

// Step 3: さらに要件が増えたら（ロケール対応）
const formatCurrency = (amount: number, locale: string): string => {
  return new Intl.NumberFormat(locale, {
    style: 'currency',
    currency: locale === 'en-US' ? 'USD' : 'EUR',
  }).format(amount);
};
```

### 早すぎる抽象化

```typescript
// 悪い例: 使用箇所1つで汎用フレームワーク構築
abstract class BaseCRUDService<T> {
  abstract getAll(): Promise<T[]>;
  abstract getById(id: string): Promise<T>;
  abstract create(data: Partial<T>): Promise<T>;
  abstract update(id: string, data: Partial<T>): Promise<T>;
  abstract delete(id: string): Promise<void>;
}
class GenericRepository<T> { /* 300行 */ }

// 良い例: 今必要な関数だけ
const getUsers = async (): Promise<User[]> => {
  return db.query('SELECT * FROM users');
};

const getUserById = async (id: string): Promise<User | null> => {
  return db.query('SELECT * FROM users WHERE id = $1', [id]);
};
// 3箇所以上で同じパターンが出てきたら抽象化を検討する
```
