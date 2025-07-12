// 移除位置功能测试脚本
// 在浏览器控制台中运行此脚本来测试功能

console.log('🗑️ 移除位置功能测试开始...');

// 测试移除位置功能
async function testRemoveLocation() {
    console.log('📋 测试步骤:');
    console.log('1. 检查当前用户位置状态');
    console.log('2. 调用移除位置API');
    console.log('3. 验证状态更新');
    
    try {
        // 步骤1: 检查当前状态
        console.log('\n🔍 步骤1: 检查当前状态...');
        
        // 检查用户是否已分享位置
        const hasLocation = !!window.currentUser?.location;
        console.log('用户已分享位置:', hasLocation);
        
        if (!hasLocation) {
            console.log('⚠️ 用户未分享位置，无法测试移除功能');
            return;
        }
        
        console.log('当前位置:', window.currentUser.location);
        
        // 步骤2: 调用API
        console.log('\n🗑️ 步骤2: 调用移除位置API...');
        
        const response = await fetch('/api/where-is-my-friends/locations', {
            method: 'DELETE',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''
            }
        });
        
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }
        
        const result = await response.json();
        console.log('✅ API响应:', result);
        
        // 步骤3: 验证状态
        console.log('\n📊 步骤3: 验证状态更新...');
        
        // 等待一下让前端状态更新
        setTimeout(() => {
            const newHasLocation = !!window.currentUser?.location;
            console.log('移除后用户位置状态:', newHasLocation);
            
            if (!newHasLocation) {
                console.log('✅ 位置信息已成功移除');
            } else {
                console.log('❌ 位置信息未被移除');
            }
        }, 1000);
        
    } catch (error) {
        console.error('❌ 测试失败:', error);
    }
}

// 测试按钮点击功能
function testRemoveButton() {
    console.log('🔘 测试移除按钮...');
    
    // 查找移除按钮
    const removeButton = document.querySelector('button[data-action="removeLocation"]') || 
                        document.querySelector('button:contains("移除")') ||
                        document.querySelector('button:contains("删除")');
    
    if (removeButton) {
        console.log('✅ 找到移除按钮');
        console.log('按钮文本:', removeButton.textContent.trim());
        console.log('按钮禁用状态:', removeButton.disabled);
        
        // 检查按钮是否应该可见
        const hasLocation = !!window.currentUser?.location;
        if (hasLocation) {
            console.log('✅ 用户有位置，移除按钮应该可见');
        } else {
            console.log('⚠️ 用户无位置，移除按钮可能不可见');
        }
        
    } else {
        console.log('❌ 未找到移除按钮');
        
        // 列出所有按钮
        const buttons = document.querySelectorAll('button');
        console.log('页面上的按钮:');
        buttons.forEach((button, index) => {
            console.log(`${index + 1}. "${button.textContent.trim()}"`);
        });
    }
}

// 检查页面状态
function checkPageState() {
    console.log('📄 检查页面状态...');
    
    // 检查用户位置状态
    const hasLocation = !!window.currentUser?.location;
    console.log('用户已分享位置:', hasLocation);
    
    // 检查位置状态显示
    const locationStatus = document.querySelector('.location-status');
    const locationSetup = document.querySelector('.location-setup');
    
    if (locationStatus) {
        console.log('✅ 显示位置已分享状态');
    } else if (locationSetup) {
        console.log('✅ 显示位置设置界面');
    } else {
        console.log('⚠️ 未找到位置状态显示');
    }
    
    // 检查错误信息
    const errors = document.querySelectorAll('.alert-error');
    if (errors.length > 0) {
        console.log('⚠️ 发现错误信息:', errors.length, '个');
        errors.forEach((error, index) => {
            console.log(`错误 ${index + 1}:`, error.textContent.trim());
        });
    }
    
    // 检查用户列表
    const userList = document.querySelector('.users-list');
    if (userList) {
        const userCards = userList.querySelectorAll('.user-card');
        console.log('用户卡片数量:', userCards.length);
    }
}

// 模拟移除位置操作
async function simulateRemoveLocation() {
    console.log('🎭 模拟移除位置操作...');
    
    try {
        // 模拟点击移除按钮
        const removeButton = document.querySelector('button[data-action="removeLocation"]') || 
                            document.querySelector('button:contains("移除")');
        
        if (removeButton) {
            console.log('点击移除按钮...');
            removeButton.click();
            
            // 等待操作完成
            setTimeout(() => {
                console.log('检查操作结果...');
                checkPageState();
            }, 2000);
        } else {
            console.log('❌ 未找到移除按钮');
        }
    } catch (error) {
        console.error('❌ 模拟操作失败:', error);
    }
}

// 运行完整测试
async function runFullTest() {
    console.log('🚀 开始完整测试...\n');
    
    // 检查页面状态
    checkPageState();
    
    // 测试按钮
    testRemoveButton();
    
    // 测试API调用
    await testRemoveLocation();
    
    // 模拟操作
    await simulateRemoveLocation();
    
    console.log('\n✅ 测试完成！');
}

// 导出函数供外部调用
window.removeLocationTest = {
    testRemoveLocation,
    testRemoveButton,
    checkPageState,
    simulateRemoveLocation,
    runFullTest
};

console.log('📝 测试脚本已加载。运行 removeLocationTest.runFullTest() 开始测试。');

// 自动运行基础检查
setTimeout(() => {
    console.log('\n🔍 自动运行基础检查...');
    checkPageState();
}, 1000); 