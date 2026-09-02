class_name OrderTypeData
extends Resource
## Тип заказа. Порт ORDER_META (orders.js:7) + ratingPerOrder (config.js:133).
##
## Ключи приведены к единому виду: тип &"tour" несёт свой rating_reward,
## в оригинале был рассинхрон ORDER_META.tour vs ratingPerOrder.tourist,
## из-за которого срабатывал скрытый fallback `|| 8`.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Буква на маркере заказа.
@export var icon: String = "P"
@export var color: Color = Color.WHITE

@export_group("Экономика")
## Множитель оплаты.
@export var pay_mult: float = 1.0
## Лимит времени, сек. 0 — без лимита.
@export var time_limit: float = 0.0
@export var rating_reward: int = 4

@export_group("Условия появления")
## Вероятность появления днём (доля в общем распределении).
@export var day_weight: float = 1.0
@export var night_weight: float = 1.0
## Требуемая вместимость машины.
@export var required_capacity: int = 1
## Требуемый рейтинг игрока.
@export var required_rating: int = 0
## Число точек высадки.
@export var stops: int = 1

@export_group("Особое поведение")
## Пассажира нет — везём груз (package).
@export var is_parcel: bool = false
## Аккуратная езда: при сильном ударе клиент уходит (vip).
@export var leaves_on_crash: bool = false
## Может передумать и сменить адрес по пути (drunk).
@export var may_change_destination: bool = false
## Экскурсия по достопримечательностям (tour).
@export var is_tour: bool = false
@export var tip_mult: float = 1.0

@export_group("Диалоги")
@export var quotes_pickup: QuoteBank
@export var quotes_dropoff: QuoteBank
@export var quotes_detour: QuoteBank
@export var quotes_crash: QuoteBank
