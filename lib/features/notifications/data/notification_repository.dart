import'login_notification.dart'; 

class NotificationRepository{
    NotificationRepository._();
    static final NotificationRepository instance =NotificationRepository._();
    Future<LoginNotification?> fetchLoginNotification()async{
        return const LoginNotification(
            title: 'Notifications',
            body: '''Dear LCOs,

Bill deletion requests will be accepted only until the evening of the 26th of every month. Any requests submitted after this will be processed next month.

Magikdigi-ൽ broadband customer unmapping option available ആയിട്ടുണ്ട്.
Path : Broadband > Customer Operation > Unmap customer.

Note :- Broadband payment ചെയ്യുമ്പോൾ ശ്രദ്ധിച്ചു മാത്രം ചെയ്യുക.

Magik-Digi support land phone number : 0480-2080005,
Lco Name Hrithik 
Heres the new policy
New Descrption need to be added 
hello everyone heres the new description need to follow

As Per New policy
Every price is now increase 
detailed information will be provided 

keep checking for more information 
''',



        );
    }

}