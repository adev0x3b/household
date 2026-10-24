# Glossary

[Documentation](../README.md) › [Architecture](README.md)

One word per concept, on every screen and in both languages. Where the code's name differs from what people read, the last column says why. A new string uses the word in this table, and `test/i18n_vocabulary_test.rb` fails on the synonyms the app has retired. Add a row here when a new concept gets a name, and a rule there when a word is taken out of use.

## People and places

| English | Italian | Code | Why the code differs |
|---|---|---|---|
| Household | Casa | `Household` | |
| Housemate | membro della casa | `Profile#housemates` | A person who signs in is a `Profile`, and the screens show their name. |
| Admin | amministratore (menu group: Amministrazione) | `role: admin`, the `Admin::` namespace | One word everywhere for whoever runs the installation. |

## The calendar

| English | Italian | Code | Why the code differs |
|---|---|---|---|
| Series, "this day" | serie, questo giorno | `Event`, `Occurrence` | People never see "occurrence"; a day of a series is just a day. |
| Task | Attività | `Task` | |
| Appointment | Appuntamento | `Appointment` | |
| Medication, dose | Farmaco, dose | `Medication` | A dose is one day of the series. |
| Meal | Pasto | `Meal` | |
| Lab result | Esame | `LabTestResult` | The class is named for what it holds, the result of a lab test; its table and entries follow it. |
| Value (of a lab result) | valore | `LabTestResultEntry` | |
| Analyte | Analita | `Analyte` | |
| Reference range | intervallo di riferimento | `ReferenceRange` | |
| Payment | Pagamento | `Transaction` | One series is an expense for the housemate who pays and income for the one who is paid, so the model is named for money moving in either direction ([the calendar](calendar.md)). |
| Expense, Expenses | Uscita, Uscite | `Transaction` of kind `expense` | |
| Income | Entrata, Entrate | `Transaction` of kind `income` | |
| Healthcare expenses | Spese sanitarie | | The fixed Italian term; "Spese" appears only in this phrase. |
| Collection | Raccolta | `Collection` | A therapy is a collection in Healthcare. |

A done day says what happened in its kind's own word. The same word is the status and the toast.

| Kind | English | Italian |
|---|---|---|
| Task | Done | Completata |
| Appointment | Attended | Svolto |
| Medication | Taken | Assunta |
| Meal | Eaten | Consumato |
| Lab result | Recorded | Registrato |
| Payment | Paid | Pagato |

In code every one of them is `status: :completed`, set only through `complete!`.

## Pantry and shelf

| English | Italian | Code | Why the code differs |
|---|---|---|---|
| Pantry | Dispensa | `Reports::Pantry` | |
| Grocery list | Lista della spesa | `GroceryList` | "Spesa" alone means groceries, never an expense. |
| Supply | Fornitura | `Supply` | "Scorta" is the stock a supply has left, not the supply. |
| Purchase history | Cronologia acquisti | | |
| Bookshelf | Libreria | `Bookshelf` | |

## Messages, files and links

| English | Italian | Code | Why the code differs |
|---|---|---|---|
| Conversation (between housemates) | conversazione | `Conversation` | "Chat" is only the assistant's. |
| Chat (with the assistant) | chat | `Assistant::Chat` | |
| Photo | Foto | `Message#images` | A photo someone sends is stored as an image attachment; "Image" is also the name of a file's kind. |
| File | File | `Upload` | A file is what was uploaded; the section is called Files. |
| Public link | link pubblico | `UploadLink` | Anyone with the link can download a file, which is what "public" says; "link" alone is the housemates' calendar link. |
| Link (between housemates) | Collegamento | `Link` | Asking for one is an invitation (invito). |
| Request (a change held for its owner) | richiesta | `LinkApproval` | The owner approves or declines it; the person who asked withdraws it. |

## Words that look alike

Some words mean two things, and each keeps both on purpose:

- **Chat and conversation.** Housemates have conversations; the assistant has chats.
- **Image and photo.** A file's kind is Image; a picture someone sends is a photo.
- **Link and public link.** A link joins two housemates' calendars; a public link hands one file to anyone.
- **Request and invitation.** A held change is a request; a link between housemates is an invitation until it is accepted.
