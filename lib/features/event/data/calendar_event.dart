/// One calendar event — Android parity (EventListModel / `events_list`).
class CalendarEvent {
  final String id; // calendar_event_id
  final String title; // event_title
  final String startDate; // start_date (string, as returned)
  final String endDate; // end_date
  final String status;
  final String remarks;
  final String employeeId;
  final String dealerId;
  final String createdOn;
  final String modifiedOn;

  const CalendarEvent({
    this.id = '',
    this.title = '',
    this.startDate = '',
    this.endDate = '',
    this.status = '',
    this.remarks = '',
    this.employeeId = '',
    this.dealerId = '',
    this.createdOn = '',
    this.modifiedOn = '',
  });

  factory CalendarEvent.fromJson(Map<String, dynamic> j) {
    String s(String k) => (j[k] ?? '').toString().trim();
    return CalendarEvent(
      id: s('calendar_event_id'),
      title: s('event_title'),
      startDate: s('start_date'),
      endDate: s('end_date'),
      status: s('status'),
      remarks: s('remarks'),
      employeeId: s('employee_id'),
      dealerId: s('dealer_id'),
      createdOn: s('created_on'),
      modifiedOn: s('modified_on'),
    );
  }
}
