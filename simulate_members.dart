import 'dart:math';
import 'lib/firebase_db.dart';

void main() async {
  print('Starting to generate  65 mock members...');
  
  final random = Random();
  final committees = ['HR', 'PR', 'PM', 'Scientific', 'Social Media', 'Charity'];
  final years = ['الفرقة الأولى', 'الفرقة الثانية', 'الفرقة الثالثة', 'الفرقة الرابعة', 'خريج'];
  final roles = ['Member', 'Head'];
  
  for (int i = 1; i <= 3; i++) {
    final id = DateTime.now().millisecondsSinceEpoch.toString() + i.toString();
    //final isMale = random.nextBool();
    final name = 'Test User $i';
    
    final memberData = {
      'id': id,
      'picture': 'https://i.pravatar.cc/150?u=$id',
      'photoUrl': 'https://i.pravatar.cc/150?u=$id',
      'fullName': 'مستخدم تجريبي رقم $i',
      'fullNameEn': name,
      'nationalId': '3000101${random.nextInt(9000000) + 1000000}',
      'birthDate': '2000-01-01',
      'committee': committees[random.nextInt(committees.length)],
      'role': roles[random.nextInt(roles.length)],
      'phone': '010${random.nextInt(90000000) + 10000000}',
      'whatsapp': '010${random.nextInt(90000000) + 10000000}',
      'address': 'القاهرة - مدينة نصر',
      'collegeYear': years[random.nextInt(years.length)],
      'email': 'user$i@example.com',
      'facebook': 'https://facebook.com/testuser$i',
      'timestamp': DateTime.now().toString()
    };
    
    final success = await FirebaseDb.saveMember(id, memberData);
    if (success) {
      print('Saved member $i');
    } else {
      print('Failed to save member $i');
    }
    
    // small delay to prevent rate limits
    await Future.delayed(Duration(milliseconds: 50));
  }
  
  print('Done!');
}
