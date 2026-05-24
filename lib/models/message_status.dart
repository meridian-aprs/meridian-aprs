/// Delivery state of an outgoing message.
///
/// Lives in the model layer (not the service layer) so the persistence layer
/// — `lib/database/` tables, DAOs, and the generated database — can reference
/// it without importing `MessageService`. `MessageService` re-exports this
/// enum for existing consumers.
enum MessageStatus { pending, acked, retrying, failed, rejected, cancelled }
